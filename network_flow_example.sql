-- Network Flow Assignment Example using HiGHS
-- Based on OR-Tools BalanceMinFlow example
-- Translates assignment problem to linear programming formulation

.load './build/release/extension/highs/highs.duckdb_extension'

-- Test the extension first
SELECT highs_version('HiGHS');

-- Step 1: Create flow variables for each arc
-- x_i_j represents flow from node i to node j
SELECT * FROM highs_create_variables('assignment_model', 'x_0_11', 0, 2, 0, 'continuous');  -- source to team A
SELECT * FROM highs_create_variables('assignment_model', 'x_0_12', 0, 2, 0, 'continuous');  -- source to team B

-- Team intermediates to workers
SELECT * FROM highs_create_variables('assignment_model', 'x_11_1', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_11_3', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_11_5', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_12_2', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_12_4', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_12_6', 0, 1, 0, 'continuous');

-- Workers to tasks (with costs as objective coefficients)
SELECT * FROM highs_create_variables('assignment_model', 'x_1_7', 0, 1, 90, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_1_8', 0, 1, 76, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_1_9', 0, 1, 75, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_1_10', 0, 1, 70, 'continuous');

SELECT * FROM highs_create_variables('assignment_model', 'x_2_7', 0, 1, 35, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_2_8', 0, 1, 85, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_2_9', 0, 1, 55, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_2_10', 0, 1, 65, 'continuous');

SELECT * FROM highs_create_variables('assignment_model', 'x_3_7', 0, 1, 125, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_3_8', 0, 1, 95, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_3_9', 0, 1, 90, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_3_10', 0, 1, 105, 'continuous');

SELECT * FROM highs_create_variables('assignment_model', 'x_4_7', 0, 1, 45, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_4_8', 0, 1, 110, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_4_9', 0, 1, 95, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_4_10', 0, 1, 115, 'continuous');

SELECT * FROM highs_create_variables('assignment_model', 'x_5_7', 0, 1, 60, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_5_8', 0, 1, 105, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_5_9', 0, 1, 80, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_5_10', 0, 1, 75, 'continuous');

SELECT * FROM highs_create_variables('assignment_model', 'x_6_7', 0, 1, 45, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_6_8', 0, 1, 65, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_6_9', 0, 1, 110, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_6_10', 0, 1, 95, 'continuous');

-- Tasks to sink
SELECT * FROM highs_create_variables('assignment_model', 'x_7_13', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_8_13', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_9_13', 0, 1, 0, 'continuous');
SELECT * FROM highs_create_variables('assignment_model', 'x_10_13', 0, 1, 0, 'continuous');

-- Step 2: Create flow conservation constraints
-- Source constraint: outflow = 4
SELECT * FROM highs_create_constraints('assignment_model', 'source_flow', 4, 4);
SELECT * FROM highs_set_coefficients('assignment_model', 'source_flow', 'x_0_11', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'source_flow', 'x_0_12', 1);

-- Team A intermediate flow conservation
SELECT * FROM highs_create_constraints('assignment_model', 'team_a_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_a_flow', 'x_0_11', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_a_flow', 'x_11_1', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_a_flow', 'x_11_3', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_a_flow', 'x_11_5', -1);

-- Team B intermediate flow conservation
SELECT * FROM highs_create_constraints('assignment_model', 'team_b_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_b_flow', 'x_0_12', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_b_flow', 'x_12_2', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_b_flow', 'x_12_4', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'team_b_flow', 'x_12_6', -1);

-- Worker flow conservation constraints
SELECT * FROM highs_create_constraints('assignment_model', 'worker_1_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_1_flow', 'x_11_1', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_1_flow', 'x_1_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_1_flow', 'x_1_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_1_flow', 'x_1_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_1_flow', 'x_1_10', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'worker_2_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_2_flow', 'x_12_2', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_2_flow', 'x_2_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_2_flow', 'x_2_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_2_flow', 'x_2_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_2_flow', 'x_2_10', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'worker_3_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_3_flow', 'x_11_3', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_3_flow', 'x_3_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_3_flow', 'x_3_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_3_flow', 'x_3_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_3_flow', 'x_3_10', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'worker_4_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_4_flow', 'x_12_4', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_4_flow', 'x_4_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_4_flow', 'x_4_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_4_flow', 'x_4_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_4_flow', 'x_4_10', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'worker_5_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_5_flow', 'x_11_5', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_5_flow', 'x_5_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_5_flow', 'x_5_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_5_flow', 'x_5_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_5_flow', 'x_5_10', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'worker_6_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_6_flow', 'x_12_6', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_6_flow', 'x_6_7', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_6_flow', 'x_6_8', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_6_flow', 'x_6_9', -1);
SELECT * FROM highs_set_coefficients('assignment_model', 'worker_6_flow', 'x_6_10', -1);

-- Task flow conservation constraints (each task needs exactly 1 worker)
SELECT * FROM highs_create_constraints('assignment_model', 'task_7_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_1_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_2_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_3_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_4_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_5_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_6_7', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_7_flow', 'x_7_13', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'task_8_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_1_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_2_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_3_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_4_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_5_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_6_8', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_8_flow', 'x_8_13', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'task_9_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_1_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_2_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_3_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_4_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_5_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_6_9', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_9_flow', 'x_9_13', -1);

SELECT * FROM highs_create_constraints('assignment_model', 'task_10_flow', 0, 0);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_1_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_2_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_3_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_4_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_5_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_6_10', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'task_10_flow', 'x_10_13', -1);

-- Sink constraint: inflow = 4 
SELECT * FROM highs_create_constraints('assignment_model', 'sink_flow', 4, 4);
SELECT * FROM highs_set_coefficients('assignment_model', 'sink_flow', 'x_7_13', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'sink_flow', 'x_8_13', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'sink_flow', 'x_9_13', 1);
SELECT * FROM highs_set_coefficients('assignment_model', 'sink_flow', 'x_10_13', 1);

-- Step 3: Solve the model and get total cost
WITH solution AS (
  SELECT * FROM highs_solve('assignment_model')
),
cost_vars AS (
  SELECT variable_name, solution_value
  FROM solution 
  WHERE solution_value > 0 
    AND variable_name LIKE 'x_%_%'
    AND variable_name NOT LIKE 'x_0_%'   -- exclude source flows
    AND variable_name NOT LIKE 'x_%_13'  -- exclude sink flows
    AND variable_name NOT LIKE 'x_11_%'  -- exclude team intermediate flows
    AND variable_name NOT LIKE 'x_12_%'  -- exclude team intermediate flows
),
cost_calculation AS (
  SELECT 
    CASE variable_name
      WHEN 'x_1_7' THEN 90 * solution_value
      WHEN 'x_1_8' THEN 76 * solution_value  
      WHEN 'x_1_9' THEN 75 * solution_value
      WHEN 'x_1_10' THEN 70 * solution_value
      WHEN 'x_2_7' THEN 35 * solution_value
      WHEN 'x_2_8' THEN 85 * solution_value
      WHEN 'x_2_9' THEN 55 * solution_value
      WHEN 'x_2_10' THEN 65 * solution_value
      WHEN 'x_3_7' THEN 125 * solution_value
      WHEN 'x_3_8' THEN 95 * solution_value
      WHEN 'x_3_9' THEN 90 * solution_value
      WHEN 'x_3_10' THEN 105 * solution_value
      WHEN 'x_4_7' THEN 45 * solution_value
      WHEN 'x_4_8' THEN 110 * solution_value
      WHEN 'x_4_9' THEN 95 * solution_value
      WHEN 'x_4_10' THEN 115 * solution_value
      WHEN 'x_5_7' THEN 60 * solution_value
      WHEN 'x_5_8' THEN 105 * solution_value
      WHEN 'x_5_9' THEN 80 * solution_value
      WHEN 'x_5_10' THEN 75 * solution_value
      WHEN 'x_6_7' THEN 45 * solution_value
      WHEN 'x_6_8' THEN 65 * solution_value
      WHEN 'x_6_9' THEN 110 * solution_value
      WHEN 'x_6_10' THEN 95 * solution_value
      ELSE 0
    END as cost_contribution,
    variable_name,
    solution_value
  FROM cost_vars
)
SELECT 'Total cost = ' || CAST(SUM(cost_contribution) AS INTEGER) as result
FROM cost_calculation;

-- Show worker-task assignments with costs
WITH solution AS (
  SELECT * FROM highs_solve('assignment_model')
),
assignments AS (
  SELECT 
    variable_name,
    solution_value,
    SPLIT_PART(variable_name, '_', 2) as worker,
    SPLIT_PART(variable_name, '_', 3) as task,
    CASE variable_name
      WHEN 'x_1_7' THEN 90
      WHEN 'x_1_8' THEN 76  
      WHEN 'x_1_9' THEN 75
      WHEN 'x_1_10' THEN 70
      WHEN 'x_2_7' THEN 35
      WHEN 'x_2_8' THEN 85
      WHEN 'x_2_9' THEN 55
      WHEN 'x_2_10' THEN 65
      WHEN 'x_3_7' THEN 125
      WHEN 'x_3_8' THEN 95
      WHEN 'x_3_9' THEN 90
      WHEN 'x_3_10' THEN 105
      WHEN 'x_4_7' THEN 45
      WHEN 'x_4_8' THEN 110
      WHEN 'x_4_9' THEN 95
      WHEN 'x_4_10' THEN 115
      WHEN 'x_5_7' THEN 60
      WHEN 'x_5_8' THEN 105
      WHEN 'x_5_9' THEN 80
      WHEN 'x_5_10' THEN 75
      WHEN 'x_6_7' THEN 45
      WHEN 'x_6_8' THEN 65
      WHEN 'x_6_9' THEN 110
      WHEN 'x_6_10' THEN 95
      ELSE 0
    END as cost
  FROM solution 
  WHERE solution_value > 0 
    AND variable_name LIKE 'x_%_%'
    AND SPLIT_PART(variable_name, '_', 2) IN ('1','2','3','4','5','6')  -- workers
    AND SPLIT_PART(variable_name, '_', 3) IN ('7','8','9','10')         -- tasks
)
SELECT 
  'Worker ' || worker || ' assigned to task ' || task || '.  Cost = ' || CAST(cost AS INTEGER) as assignment
FROM assignments 
WHERE solution_value > 0
ORDER BY CAST(worker AS INTEGER);