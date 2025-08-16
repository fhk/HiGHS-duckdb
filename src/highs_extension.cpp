#define DUCKDB_EXTENSION_MAIN

#include "highs_extension.hpp"
#include "duckdb.hpp"
#include "duckdb/common/exception.hpp"
#include "duckdb/main/extension_util.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/scalar_function.hpp"
#include "duckdb/function/table_function.hpp"
#include <duckdb/parser/parsed_data/create_scalar_function_info.hpp>
#include <duckdb/parser/parsed_data/create_table_function_info.hpp>

// OpenSSL linked through vcpkg
#include <openssl/opensslv.h>

// HiGHS headers
#include "Highs.h"

#include <unordered_map>
#include <mutex>
#include <memory>

namespace duckdb {

// Model registry to store HiGHS models and their metadata
struct HighsModelInfo {
  HighsModel model;
  std::unordered_map<std::string, int> variable_indices;
  std::unordered_map<std::string, int> constraint_indices;
  std::vector<std::string> variable_names;
  std::vector<std::string> constraint_names;
  std::vector<double> obj_coefficients;
  std::vector<double> var_lower_bounds;
  std::vector<double> var_upper_bounds;
  std::vector<double> constraint_lower_bounds;
  std::vector<double> constraint_upper_bounds;
  std::vector<std::vector<std::pair<int, double>>>
      constraint_coefficients;             // [constraint_idx][{var_idx, coeff}]
  std::vector<std::string> variable_types; // 'continuous', 'integer', 'binary'
  int next_var_index = 0;
  int next_constraint_index = 0;

  HighsModelInfo() { model.lp_.sense_ = ObjSense::kMinimize; }
};

class HighsModelRegistry {
private:
  std::unordered_map<std::string, std::unique_ptr<HighsModelInfo>> models;
  std::mutex mutex_;

public:
  static HighsModelRegistry &Instance() {
    static HighsModelRegistry instance;
    return instance;
  }

  HighsModelInfo *GetOrCreateModel(const std::string &model_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = models.find(model_name);
    if (it == models.end()) {
      models[model_name] = make_uniq<HighsModelInfo>();
    }
    return models[model_name].get();
  }

  HighsModelInfo *GetModel(const std::string &model_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = models.find(model_name);
    return (it != models.end()) ? it->second.get() : nullptr;
  }

  void RemoveModel(const std::string &model_name) {
    std::lock_guard<std::mutex> lock(mutex_);
    models.erase(model_name);
  }
};

// Data structures for function bind data
struct HighsCreateVariablesData : public TableFunctionData {
  std::string model_name;
  std::string variable_name;
  double lower_bound;
  double upper_bound;
  double obj_coefficient;
  std::string var_type;
};

struct HighsCreateConstraintsData : public TableFunctionData {
  std::string model_name;
  std::string constraint_name;
  double lower_bound;
  double upper_bound;
};

struct HighsSetCoefficientsData : public TableFunctionData {
  std::string model_name;
  std::string constraint_name;
  std::string variable_name;
  double coefficient;
};

struct HighsSolveData : public TableFunctionData {
  std::string model_name;
};

struct HighsSolveGlobalState : public GlobalTableFunctionState {
  bool solved = false;
  std::vector<double> solution_values;
  std::vector<double> reduced_costs;
  HighsModelStatus model_status;
  idx_t current_row = 0;
};

// Forward declaration
static void LoadInternal(DuckDB &db);

inline void HighsVersionScalarFun(DataChunk &args, ExpressionState &state,
                                  Vector &result) {
  auto &name_vector = args.data[0];
  UnaryExecutor::Execute<string_t, string_t>(
      name_vector, result, args.size(), [&](string_t name) {
        return StringVector::AddString(
            result,
            "Hello " + name.GetString() + ", HiGHS version: " + highsVersion());
      });
}

inline void HighsOpenSSLVersionScalarFun(DataChunk &args,
                                         ExpressionState &state,
                                         Vector &result) {
  auto &name_vector = args.data[0];
  UnaryExecutor::Execute<string_t, string_t>(
      name_vector, result, args.size(), [&](string_t name) {
        return StringVector::AddString(
            result, "Hello " + name.GetString() +
                        ", HiGHS version: " + highsVersion() +
                        ", OpenSSL version: " + OPENSSL_VERSION_TEXT);
      });
}

void HighsExtension::Load(DuckDB &db) { LoadInternal(db); }
std::string HighsExtension::Name() { return "highs"; }

std::string HighsExtension::Version() const {
#ifdef EXT_VERSION_HIGHS
  return EXT_VERSION_HIGHS;
#else
  return "";
#endif
}

// Global state for single-row table functions
struct SingleRowGlobalState : public GlobalTableFunctionState {
  bool finished = false;
};

// Table function for creating variables from a table
struct HighsCreateVariablesFunction {
  static void CreateVariablesFunction(ClientContext &context,
                                      TableFunctionInput &data_p,
                                      DataChunk &output) {
    auto &bind_data = data_p.bind_data->Cast<HighsCreateVariablesData>();
    auto &global_state = data_p.global_state->Cast<SingleRowGlobalState>();

    // If we've already output a row, we're done
    if (global_state.finished) {
      output.SetCardinality(0);
      return;
    }

    // Get model from registry
    auto *model_info =
        HighsModelRegistry::Instance().GetOrCreateModel(bind_data.model_name);

    try {
      // Check if variable already exists
      if (model_info->variable_indices.find(bind_data.variable_name) !=
          model_info->variable_indices.end()) {
        throw std::runtime_error("Variable '" + bind_data.variable_name +
                                 "' already exists in model '" +
                                 bind_data.model_name + "'");
      }

      // Store variable info
      int var_index = model_info->next_var_index++;
      model_info->variable_indices[bind_data.variable_name] = var_index;
      model_info->variable_names.push_back(bind_data.variable_name);
      model_info->obj_coefficients.push_back(bind_data.obj_coefficient);
      model_info->var_lower_bounds.push_back(bind_data.lower_bound);
      model_info->var_upper_bounds.push_back(bind_data.upper_bound);
      model_info->variable_types.push_back(bind_data.var_type);

      // Update model dimensions
      model_info->model.lp_.num_col_ = model_info->next_var_index;

      // Set output
      output.SetCardinality(1);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[0]);
      auto variable_index_vector =
          FlatVector::GetData<string_t>(output.data[1]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[2]);

      std::string index_str =
          bind_data.variable_name + "_" + std::to_string(var_index);
      variable_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.variable_name);
      variable_index_vector[0] =
          StringVector::AddString(output.data[1], index_str);
      status_vector[0] = StringVector::AddString(output.data[2], "SUCCESS");

    } catch (const std::exception &e) {
      output.SetCardinality(1);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[0]);
      auto variable_index_vector =
          FlatVector::GetData<string_t>(output.data[1]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[2]);

      variable_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.variable_name);
      variable_index_vector[0] =
          StringVector::AddString(output.data[1], "ERROR"); // Error case
      status_vector[0] = StringVector::AddString(
          output.data[2], "ERROR: " + std::string(e.what()));
    }

    global_state.finished = true;
  }

  static unique_ptr<FunctionData>
  CreateVariablesBind(ClientContext &context, TableFunctionBindInput &input,
                      vector<LogicalType> &return_types,
                      vector<string> &names) {
    auto result = make_uniq<HighsCreateVariablesData>();

    // Extract parameters from input.inputs (these are Value objects)
    if (input.inputs.size() != 6) {
      throw BinderException(
          "highs_create_variables expects exactly 6 parameters: model_name, "
          "variable_name, lower_bound, upper_bound, obj_coefficient, var_type");
    }

    result->model_name = input.inputs[0].GetValue<string>();
    result->variable_name = input.inputs[1].GetValue<string>();
    result->lower_bound = input.inputs[2].GetValue<double>();
    result->upper_bound = input.inputs[3].GetValue<double>();
    result->obj_coefficient = input.inputs[4].GetValue<double>();
    result->var_type = input.inputs[5].GetValue<string>();

    // Define output schema
    names.emplace_back("variable_name");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("variable_index");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("status");
    return_types.emplace_back(LogicalType::VARCHAR);

    return std::move(result);
  }

  static unique_ptr<GlobalTableFunctionState>
  CreateVariablesInit(ClientContext &context, TableFunctionInitInput &input) {
    return make_uniq<SingleRowGlobalState>();
  }
};

// Table function for creating constraints from a table
struct HighsCreateConstraintsFunction {
  static void CreateConstraintsFunction(ClientContext &context,
                                        TableFunctionInput &data_p,
                                        DataChunk &output) {
    auto &bind_data = data_p.bind_data->Cast<HighsCreateConstraintsData>();
    auto &global_state = data_p.global_state->Cast<SingleRowGlobalState>();

    // If we've already output a row, we're done
    if (global_state.finished) {
      output.SetCardinality(0);
      return;
    }

    // Get model from registry
    auto *model_info =
        HighsModelRegistry::Instance().GetOrCreateModel(bind_data.model_name);

    try {
      // Check if constraint already exists
      if (model_info->constraint_indices.find(bind_data.constraint_name) !=
          model_info->constraint_indices.end()) {
        throw std::runtime_error("Constraint '" + bind_data.constraint_name +
                                 "' already exists in model '" +
                                 bind_data.model_name + "'");
      }

      // Store constraint info
      int constraint_index = model_info->next_constraint_index++;
      model_info->constraint_indices[bind_data.constraint_name] =
          constraint_index;
      model_info->constraint_names.push_back(bind_data.constraint_name);
      model_info->constraint_lower_bounds.push_back(bind_data.lower_bound);
      model_info->constraint_upper_bounds.push_back(bind_data.upper_bound);
      model_info->constraint_coefficients.push_back(
          std::vector<std::pair<int, double>>());

      // Update model dimensions
      model_info->model.lp_.num_row_ = model_info->next_constraint_index;

      // Set output
      output.SetCardinality(1);
      auto constraint_name_vector =
          FlatVector::GetData<string_t>(output.data[0]);
      auto constraint_index_vector =
          FlatVector::GetData<string_t>(output.data[1]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[2]);

      std::string index_str =
          bind_data.constraint_name + "_" + std::to_string(constraint_index);
      constraint_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.constraint_name);
      constraint_index_vector[0] =
          StringVector::AddString(output.data[1], index_str);
      status_vector[0] = StringVector::AddString(output.data[2], "SUCCESS");

    } catch (const std::exception &e) {
      output.SetCardinality(1);
      auto constraint_name_vector =
          FlatVector::GetData<string_t>(output.data[0]);
      auto constraint_index_vector =
          FlatVector::GetData<string_t>(output.data[1]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[2]);

      constraint_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.constraint_name);
      constraint_index_vector[0] =
          StringVector::AddString(output.data[1], "ERROR"); // Error case
      status_vector[0] = StringVector::AddString(
          output.data[2], "ERROR: " + std::string(e.what()));
    }

    global_state.finished = true;
  }

  static unique_ptr<FunctionData>
  CreateConstraintsBind(ClientContext &context, TableFunctionBindInput &input,
                        vector<LogicalType> &return_types,
                        vector<string> &names) {
    auto result = make_uniq<HighsCreateConstraintsData>();

    // Extract parameters from input
    if (input.inputs.size() != 4) {
      throw BinderException(
          "highs_create_constraints expects exactly 4 parameters: model_name, "
          "constraint_name, lower_bound, upper_bound");
    }

    result->model_name = input.inputs[0].GetValue<string>();
    result->constraint_name = input.inputs[1].GetValue<string>();
    result->lower_bound = input.inputs[2].GetValue<double>();
    result->upper_bound = input.inputs[3].GetValue<double>();

    // Define output schema
    names.emplace_back("constraint_name");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("constraint_index");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("status");
    return_types.emplace_back(LogicalType::VARCHAR);

    return std::move(result);
  }

  static unique_ptr<GlobalTableFunctionState>
  CreateConstraintsInit(ClientContext &context, TableFunctionInitInput &input) {
    return make_uniq<SingleRowGlobalState>();
  }
};

// Table function for setting coefficients from a table
struct HighsSetCoefficientsFunction {
  static void SetCoefficientsFunction(ClientContext &context,
                                      TableFunctionInput &data_p,
                                      DataChunk &output) {
    auto &bind_data = data_p.bind_data->Cast<HighsSetCoefficientsData>();
    auto &global_state = data_p.global_state->Cast<SingleRowGlobalState>();

    // If we've already output a row, we're done
    if (global_state.finished) {
      output.SetCardinality(0);
      return;
    }

    // Get model from registry
    auto *model_info =
        HighsModelRegistry::Instance().GetModel(bind_data.model_name);
    if (!model_info) {
      output.SetCardinality(1);
      auto constraint_name_vector =
          FlatVector::GetData<string_t>(output.data[0]);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[1]);
      auto coefficient_vector = FlatVector::GetData<double>(output.data[2]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[3]);

      constraint_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.constraint_name);
      variable_name_vector[0] =
          StringVector::AddString(output.data[1], bind_data.variable_name);
      coefficient_vector[0] = bind_data.coefficient;
      status_vector[0] = StringVector::AddString(
          output.data[3],
          "ERROR: Model '" + bind_data.model_name + "' not found");
      global_state.finished = true;
      return;
    }

    try {
      // Find variable and constraint indices
      auto var_it = model_info->variable_indices.find(bind_data.variable_name);
      auto constraint_it =
          model_info->constraint_indices.find(bind_data.constraint_name);

      if (var_it == model_info->variable_indices.end()) {
        throw std::runtime_error("Variable '" + bind_data.variable_name +
                                 "' not found in model '" +
                                 bind_data.model_name + "'");
      }

      if (constraint_it == model_info->constraint_indices.end()) {
        throw std::runtime_error("Constraint '" + bind_data.constraint_name +
                                 "' not found in model '" +
                                 bind_data.model_name + "'");
      }

      int var_index = var_it->second;
      int constraint_index = constraint_it->second;

      // Store the coefficient for later matrix construction
      model_info->constraint_coefficients[constraint_index].push_back(
          {var_index, bind_data.coefficient});

      // Set output
      output.SetCardinality(1);
      auto constraint_name_vector =
          FlatVector::GetData<string_t>(output.data[0]);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[1]);
      auto coefficient_vector = FlatVector::GetData<double>(output.data[2]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[3]);

      constraint_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.constraint_name);
      variable_name_vector[0] =
          StringVector::AddString(output.data[1], bind_data.variable_name);
      coefficient_vector[0] = bind_data.coefficient;
      status_vector[0] = StringVector::AddString(output.data[3], "SUCCESS");

    } catch (const std::exception &e) {
      output.SetCardinality(1);
      auto constraint_name_vector =
          FlatVector::GetData<string_t>(output.data[0]);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[1]);
      auto coefficient_vector = FlatVector::GetData<double>(output.data[2]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[3]);

      constraint_name_vector[0] =
          StringVector::AddString(output.data[0], bind_data.constraint_name);
      variable_name_vector[0] =
          StringVector::AddString(output.data[1], bind_data.variable_name);
      coefficient_vector[0] = bind_data.coefficient;
      status_vector[0] = StringVector::AddString(
          output.data[3], "ERROR: " + std::string(e.what()));
    }

    global_state.finished = true;
  }

  static unique_ptr<FunctionData>
  SetCoefficientsBind(ClientContext &context, TableFunctionBindInput &input,
                      vector<LogicalType> &return_types,
                      vector<string> &names) {
    auto result = make_uniq<HighsSetCoefficientsData>();

    // Extract parameters from input
    if (input.inputs.size() != 4) {
      throw BinderException(
          "highs_set_coefficients expects exactly 4 parameters: model_name, "
          "constraint_name, variable_name, coefficient");
    }

    result->model_name = input.inputs[0].GetValue<string>();
    result->constraint_name = input.inputs[1].GetValue<string>();
    result->variable_name = input.inputs[2].GetValue<string>();
    result->coefficient = input.inputs[3].GetValue<double>();

    // Define output schema
    names.emplace_back("constraint_name");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("variable_name");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("coefficient");
    return_types.emplace_back(LogicalType::DOUBLE);
    names.emplace_back("status");
    return_types.emplace_back(LogicalType::VARCHAR);

    return std::move(result);
  }

  static unique_ptr<GlobalTableFunctionState>
  SetCoefficientsInit(ClientContext &context, TableFunctionInitInput &input) {
    return make_uniq<SingleRowGlobalState>();
  }
};

// Table function for solving model and returning results
struct HighsSolveFunction {
  static void SolveFunction(ClientContext &context, TableFunctionInput &data_p,
                            DataChunk &output) {
    auto &bind_data = data_p.bind_data->Cast<HighsSolveData>();
    auto &global_state = data_p.global_state->Cast<HighsSolveGlobalState>();

    // Get model from registry
    auto *model_info =
        HighsModelRegistry::Instance().GetModel(bind_data.model_name);
    if (!model_info) {
      output.SetCardinality(1);
      auto variable_name_vector = FlatVector::GetData<string_t>(output.data[0]);
      auto variable_index_vector =
          FlatVector::GetData<string_t>(output.data[1]);
      auto solution_value_vector = FlatVector::GetData<double>(output.data[2]);
      auto reduced_cost_vector = FlatVector::GetData<double>(output.data[3]);
      auto status_vector = FlatVector::GetData<string_t>(output.data[4]);

      variable_name_vector[0] = StringVector::AddString(output.data[0], "N/A");
      variable_index_vector[0] =
          StringVector::AddString(output.data[1], "ERROR");
      solution_value_vector[0] = 0.0;
      reduced_cost_vector[0] = 0.0;
      status_vector[0] = StringVector::AddString(
          output.data[4],
          "ERROR: Model '" + bind_data.model_name + "' not found");
      return;
    }

    // Solve the model if not already solved
    if (!global_state.solved) {
      try {
        // Build the complete model
        model_info->model.lp_.col_cost_ = model_info->obj_coefficients;
        model_info->model.lp_.col_lower_ = model_info->var_lower_bounds;
        model_info->model.lp_.col_upper_ = model_info->var_upper_bounds;
        model_info->model.lp_.row_lower_ = model_info->constraint_lower_bounds;
        model_info->model.lp_.row_upper_ = model_info->constraint_upper_bounds;

        // Build constraint matrix in column-wise format
        std::vector<HighsInt> start;
        std::vector<HighsInt> index;
        std::vector<double> value;

        start.push_back(0);
        for (int col = 0; col < model_info->next_var_index; col++) {
          for (int row = 0; row < model_info->next_constraint_index; row++) {
            for (const auto &coeff : model_info->constraint_coefficients[row]) {
              if (coeff.first == col) {
                index.push_back(row);
                value.push_back(coeff.second);
              }
            }
          }
          start.push_back(index.size());
        }

        model_info->model.lp_.a_matrix_.format_ = MatrixFormat::kColwise;
        model_info->model.lp_.a_matrix_.start_ = start;
        model_info->model.lp_.a_matrix_.index_ = index;
        model_info->model.lp_.a_matrix_.value_ = value;

        // Configure integer/binary variables
        std::vector<HighsVarType> var_types;
        for (int i = 0; i < model_info->next_var_index; i++) {
          const std::string &var_type = model_info->variable_types[i];
          if (var_type == "binary") {
            var_types.push_back(HighsVarType::kInteger);
            // For binary variables, ensure bounds are [0,1]
            model_info->model.lp_.col_lower_[i] =
                std::max(0.0, model_info->model.lp_.col_lower_[i]);
            model_info->model.lp_.col_upper_[i] =
                std::min(1.0, model_info->model.lp_.col_upper_[i]);
          } else if (var_type == "integer") {
            var_types.push_back(HighsVarType::kInteger);
          } else {
            var_types.push_back(HighsVarType::kContinuous);
          }
        }
        model_info->model.lp_.integrality_ = var_types;

        // Solve the model
        Highs highs;
        HighsStatus status = highs.passModel(model_info->model);
        if (status != HighsStatus::kOk) {
          throw std::runtime_error("Failed to pass model to HiGHS");
        }

        status = highs.run();
        if (status != HighsStatus::kOk) {
          throw std::runtime_error("Failed to solve model");
        }

        // Get solution
        const HighsSolution &solution = highs.getSolution();
        global_state.solution_values = solution.col_value;
        global_state.reduced_costs = solution.col_dual;
        global_state.model_status = highs.getModelStatus();
        global_state.solved = true;

      } catch (const std::exception &e) {
        output.SetCardinality(1);
        auto variable_name_vector =
            FlatVector::GetData<string_t>(output.data[0]);
        auto variable_index_vector =
            FlatVector::GetData<string_t>(output.data[1]);
        auto solution_value_vector =
            FlatVector::GetData<double>(output.data[2]);
        auto reduced_cost_vector = FlatVector::GetData<double>(output.data[3]);
        auto status_vector = FlatVector::GetData<string_t>(output.data[4]);

        variable_name_vector[0] =
            StringVector::AddString(output.data[0], "N/A");
        variable_index_vector[0] =
            StringVector::AddString(output.data[1], "ERROR");
        solution_value_vector[0] = 0.0;
        reduced_cost_vector[0] = 0.0;
        status_vector[0] = StringVector::AddString(
            output.data[4], "ERROR: " + std::string(e.what()));
        return;
      }
    }

    // Output solution rows
    idx_t num_variables = model_info->variable_names.size();
    idx_t current_row = global_state.current_row;

    // Check if we've output all variables
    if (current_row >= num_variables) {
      output.SetCardinality(0);
      return;
    }

    idx_t batch_size =
        std::min(num_variables - current_row, (idx_t)STANDARD_VECTOR_SIZE);
    output.SetCardinality(batch_size);
    auto variable_name_vector = FlatVector::GetData<string_t>(output.data[0]);
    auto variable_index_vector = FlatVector::GetData<string_t>(output.data[1]);
    auto solution_value_vector = FlatVector::GetData<double>(output.data[2]);
    auto reduced_cost_vector = FlatVector::GetData<double>(output.data[3]);
    auto status_vector = FlatVector::GetData<string_t>(output.data[4]);

    std::string status_str;
    switch (global_state.model_status) {
    case HighsModelStatus::kOptimal:
      status_str = "Optimal";
      break;
    case HighsModelStatus::kInfeasible:
      status_str = "Infeasible";
      break;
    case HighsModelStatus::kUnbounded:
      status_str = "Unbounded";
      break;
    default:
      status_str = "Unknown";
      break;
    }

    for (idx_t i = 0; i < batch_size; i++) {
      idx_t var_idx = current_row + i;
      std::string var_name = model_info->variable_names[var_idx];
      std::string index_str = var_name + "_" + std::to_string(var_idx);

      variable_name_vector[i] =
          StringVector::AddString(output.data[0], var_name);
      variable_index_vector[i] =
          StringVector::AddString(output.data[1], index_str);
      solution_value_vector[i] = global_state.solution_values.size() > var_idx
                                     ? global_state.solution_values[var_idx]
                                     : 0.0;
      reduced_cost_vector[i] = global_state.reduced_costs.size() > var_idx
                                   ? global_state.reduced_costs[var_idx]
                                   : 0.0;
      status_vector[i] = StringVector::AddString(output.data[4], status_str);
    }

    global_state.current_row += batch_size;
  }

  static unique_ptr<FunctionData> SolveBind(ClientContext &context,
                                            TableFunctionBindInput &input,
                                            vector<LogicalType> &return_types,
                                            vector<string> &names) {
    auto result = make_uniq<HighsSolveData>();

    // Extract parameters from input
    if (input.inputs.size() != 1) {
      throw BinderException(
          "highs_solve expects exactly 1 parameter: model_name");
    }

    result->model_name = input.inputs[0].GetValue<string>();

    // Define output schema
    names.emplace_back("variable_name");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("variable_index");
    return_types.emplace_back(LogicalType::VARCHAR);
    names.emplace_back("solution_value");
    return_types.emplace_back(LogicalType::DOUBLE);
    names.emplace_back("reduced_cost");
    return_types.emplace_back(LogicalType::DOUBLE);
    names.emplace_back("status");
    return_types.emplace_back(LogicalType::VARCHAR);

    return std::move(result);
  }

  static unique_ptr<GlobalTableFunctionState>
  SolveInit(ClientContext &context, TableFunctionInitInput &input) {
    return make_uniq<HighsSolveGlobalState>();
  }
};

static void LoadInternal(DuckDB &db) {
  // Register HiGHS version functions
  auto highs_version_function =
      ScalarFunction("highs_version", {LogicalType::VARCHAR},
                     LogicalType::VARCHAR, HighsVersionScalarFun);
  ExtensionUtil::RegisterFunction(*db.instance, highs_version_function);

  auto highs_openssl_version_function =
      ScalarFunction("highs_openssl_version", {LogicalType::VARCHAR},
                     LogicalType::VARCHAR, HighsOpenSSLVersionScalarFun);
  ExtensionUtil::RegisterFunction(*db.instance, highs_openssl_version_function);

  // Register optimization table functions
  // highs_create_variables(model_name, variable_name, lower_bound, upper_bound,
  // obj_coefficient, var_type)
  TableFunction create_variables_function(
      "highs_create_variables",
      {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE,
       LogicalType::DOUBLE, LogicalType::DOUBLE, LogicalType::VARCHAR},
      HighsCreateVariablesFunction::CreateVariablesFunction,
      HighsCreateVariablesFunction::CreateVariablesBind,
      HighsCreateVariablesFunction::CreateVariablesInit);
  ExtensionUtil::RegisterFunction(*db.instance, create_variables_function);

  // highs_create_constraints(model_name, constraint_name, lower_bound,
  // upper_bound)
  TableFunction create_constraints_function(
      "highs_create_constraints",
      {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::DOUBLE,
       LogicalType::DOUBLE},
      HighsCreateConstraintsFunction::CreateConstraintsFunction,
      HighsCreateConstraintsFunction::CreateConstraintsBind,
      HighsCreateConstraintsFunction::CreateConstraintsInit);
  ExtensionUtil::RegisterFunction(*db.instance, create_constraints_function);

  // highs_set_coefficients(model_name, constraint_name, variable_name,
  // coefficient)
  TableFunction set_coefficients_function(
      "highs_set_coefficients",
      {LogicalType::VARCHAR, LogicalType::VARCHAR, LogicalType::VARCHAR,
       LogicalType::DOUBLE},
      HighsSetCoefficientsFunction::SetCoefficientsFunction,
      HighsSetCoefficientsFunction::SetCoefficientsBind,
      HighsSetCoefficientsFunction::SetCoefficientsInit);
  ExtensionUtil::RegisterFunction(*db.instance, set_coefficients_function);

  // highs_solve(model_name)
  TableFunction solve_function(
      "highs_solve", {LogicalType::VARCHAR}, HighsSolveFunction::SolveFunction,
      HighsSolveFunction::SolveBind, HighsSolveFunction::SolveInit);
  ExtensionUtil::RegisterFunction(*db.instance, solve_function);
}

} // namespace duckdb

extern "C" {

DUCKDB_EXTENSION_API void highs_init(duckdb::DatabaseInstance &db) {
  duckdb::DuckDB db_wrapper(db);
  duckdb::LoadInternal(db_wrapper);
}

DUCKDB_EXTENSION_API const char *highs_version() {
  return duckdb::DuckDB::LibraryVersion();
}
}

#ifndef DUCKDB_EXTENSION_MAIN
#error DUCKDB_EXTENSION_MAIN not defined
#endif
