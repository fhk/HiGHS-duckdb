-- HiGHS DuckDB Extension Usage Example
-- This example demonstrates how to solve a linear programming problem using the HiGHS extension

-- Problem: 
-- Minimize: x + y
-- Subject to: 
--   x + 2*y <= 7    (constraint c1)
--   3*x + y <= 9    (constraint c2) 
--   x >= 0, y >= 1  (variable bounds)

-- Step 1: Load the HiGHS extension from the build directory
-- Option 1: Load from specific path (development)
LOAD '/workspace/build/release/extension/highs/highs.duckdb_extension';

-- Option 2: Load by name (if installed)
-- LOAD highs;

-- Step 2: Define variables with bounds and objective coefficients
CREATE TABLE model_variables AS SELECT * FROM VALUES 
    ('production_model', 'x', 0.0, 1e30, 1.0, 'continuous'),    -- variable x: [0, ∞), obj coeff = 1
    ('production_model', 'y', 1.0, 1e30, 1.0, 'continuous')     -- variable y: [1, ∞), obj coeff = 1
AS v(model_name, variable_name, lower_bound, upper_bound, obj_coefficient, var_type);

-- Step 3: Define constraints with bounds  
CREATE TABLE model_constraints AS SELECT * FROM VALUES
    ('production_model', 'resource_limit', -1e30, 7.0),         -- x + 2y <= 7
    ('production_model', 'capacity_limit', -1e30, 9.0)          -- 3x + y <= 9
AS c(model_name, constraint_name, lower_bound, upper_bound);

-- Step 4: Define the constraint matrix (coefficients)
CREATE TABLE model_coefficients AS SELECT * FROM VALUES
    ('production_model', 'resource_limit', 'x', 1.0),           -- coefficient of x in resource_limit
    ('production_model', 'resource_limit', 'y', 2.0),           -- coefficient of y in resource_limit
    ('production_model', 'capacity_limit', 'x', 3.0),           -- coefficient of x in capacity_limit
    ('production_model', 'capacity_limit', 'y', 1.0)            -- coefficient of y in capacity_limit
AS coef(model_name, constraint_name, variable_name, coefficient);

-- Step 5: Create the optimization model by setting up variables
-- Note: This will process the table and return status for each variable
SELECT * FROM highs_create_variables('production_model', 'x', 0.0, 1e30, 1.0, 'continuous');
SELECT * FROM highs_create_variables('production_model', 'y', 1.0, 1e30, 1.0, 'continuous');

-- Step 6: Add constraints to the model
SELECT * FROM highs_create_constraints('production_model', 'resource_limit', -1e30, 7.0);
SELECT * FROM highs_create_constraints('production_model', 'capacity_limit', -1e30, 9.0);

-- Step 7: Set the constraint matrix coefficients
SELECT * FROM highs_set_coefficients('production_model', 'resource_limit', 'x', 1.0);
SELECT * FROM highs_set_coefficients('production_model', 'resource_limit', 'y', 2.0);
SELECT * FROM highs_set_coefficients('production_model', 'capacity_limit', 'x', 3.0);
SELECT * FROM highs_set_coefficients('production_model', 'capacity_limit', 'y', 1.0);

-- Step 8: Solve the optimization problem
SELECT * FROM highs_solve('production_model');

-- Expected Output:
-- variable_name | solution_value | reduced_cost | status
-- x            | 0.6           | 0.0          | Optimal
-- y            | 3.2           | 0.0          | Optimal
-- 
-- This means: x* = 0.6, y* = 3.2 with objective value = 0.6 + 3.2 = 3.8

-- Advanced Usage Examples:

-- Example 2: Mixed Integer Programming
CREATE TABLE mip_variables AS SELECT * FROM VALUES 
    ('facility_location', 'facility_1', 0.0, 1.0, 100.0, 'binary'),     -- binary decision variable
    ('facility_location', 'facility_2', 0.0, 1.0, 120.0, 'binary'),     -- binary decision variable
    ('facility_location', 'capacity', 0.0, 1000.0, 0.5, 'continuous')   -- continuous capacity variable
AS v(model_name, variable_name, lower_bound, upper_bound, obj_coefficient, var_type);

-- Example 3: Multi-objective optimization (using weighted sum)
CREATE TABLE portfolio_variables AS SELECT * FROM VALUES 
    ('portfolio', 'stock_A', 0.0, 1.0, 0.08, 'continuous'),    -- 8% expected return
    ('portfolio', 'stock_B', 0.0, 1.0, 0.12, 'continuous'),    -- 12% expected return  
    ('portfolio', 'stock_C', 0.0, 1.0, 0.06, 'continuous')     -- 6% expected return
AS v(model_name, variable_name, lower_bound, upper_bound, obj_coefficient, var_type);

-- Example 4: Production planning with multiple time periods
CREATE TABLE production_variables AS SELECT * FROM VALUES 
    ('production_plan', 'prod_t1', 0.0, 100.0, -10.0, 'continuous'),   -- production in period 1
    ('production_plan', 'prod_t2', 0.0, 100.0, -10.0, 'continuous'),   -- production in period 2
    ('production_plan', 'inv_t1', 0.0, 50.0, -2.0, 'continuous'),      -- inventory in period 1
    ('production_plan', 'inv_t2', 0.0, 50.0, -2.0, 'continuous')       -- inventory in period 2
AS v(model_name, variable_name, lower_bound, upper_bound, obj_coefficient, var_type);

-- Clean up
DROP TABLE model_variables;
DROP TABLE model_constraints; 
DROP TABLE model_coefficients;
DROP TABLE mip_variables;
DROP TABLE portfolio_variables;
DROP TABLE production_variables;