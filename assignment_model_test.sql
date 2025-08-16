-- HiGHS DuckDB Extension - Data Center Site Selection Assignment Model
-- Based on: https://github.com/pozibl/pozibl.com/blob/main/work/data-center-site-selection/index.html
--
-- Problem: Select optimal data center locations to serve demand locations
-- Variables:
--   x_ij: Binary variable indicating if demand location j is assigned to data center location i
--   z_i:  Binary variable indicating if a data center is built at location i
--
-- Objective: Minimize total cost (connectivity costs + building costs)
--
-- Constraints:
--   1. Each demand location must be assigned to exactly one data center
--   2. Data center capacity constraints
--   3. Limit on number of data centers

-- Load the HiGHS extension
LOAD '/workspace/build/release/extension/highs/highs.duckdb_extension';

-- Test data: 3 potential data center locations, 4 demand locations
-- Data center locations: DC1, DC2, DC3
-- Demand locations: D1, D2, D3, D4

-- Step 1: Create assignment variables x_ij (binary variables)
-- x_ij = 1 if demand location j is assigned to data center location i, 0 otherwise
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC1_D1', 0.0, 1.0, 10.0, 'binary'); -- Cost: 10
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC1_D2', 0.0, 1.0, 15.0, 'binary'); -- Cost: 15
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC1_D3', 0.0, 1.0, 20.0, 'binary'); -- Cost: 20
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC1_D4', 0.0, 1.0, 25.0, 'binary'); -- Cost: 25

SELECT * FROM highs_create_variables('datacenter_model', 'x_DC2_D1', 0.0, 1.0, 20.0, 'binary'); -- Cost: 20
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC2_D2', 0.0, 1.0, 10.0, 'binary'); -- Cost: 10
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC2_D3', 0.0, 1.0, 15.0, 'binary'); -- Cost: 15
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC2_D4', 0.0, 1.0, 30.0, 'binary'); -- Cost: 30

SELECT * FROM highs_create_variables('datacenter_model', 'x_DC3_D1', 0.0, 1.0, 25.0, 'binary'); -- Cost: 25
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC3_D2', 0.0, 1.0, 20.0, 'binary'); -- Cost: 20
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC3_D3', 0.0, 1.0, 10.0, 'binary'); -- Cost: 10
SELECT * FROM highs_create_variables('datacenter_model', 'x_DC3_D4', 0.0, 1.0, 15.0, 'binary'); -- Cost: 15

-- Step 2: Create data center selection variables z_i (binary variables)
-- z_i = 1 if data center is built at location i, 0 otherwise
SELECT * FROM highs_create_variables('datacenter_model', 'z_DC1', 0.0, 1.0, 100.0, 'binary'); -- Building cost: 100
SELECT * FROM highs_create_variables('datacenter_model', 'z_DC2', 0.0, 1.0, 120.0, 'binary'); -- Building cost: 120
SELECT * FROM highs_create_variables('datacenter_model', 'z_DC3', 0.0, 1.0, 110.0, 'binary'); -- Building cost: 110

-- Step 3: Create constraints
-- Constraint 1: Each demand location must be assigned to exactly one data center
-- Sum over all data centers for each demand location = 1

-- Demand location D1: x_DC1_D1 + x_DC2_D1 + x_DC3_D1 = 1
SELECT * FROM highs_create_constraints('datacenter_model', 'demand_D1', 1.0, 1.0);

-- Demand location D2: x_DC1_D2 + x_DC2_D2 + x_DC3_D2 = 1
SELECT * FROM highs_create_constraints('datacenter_model', 'demand_D2', 1.0, 1.0);

-- Demand location D3: x_DC1_D3 + x_DC2_D3 + x_DC3_D3 = 1
SELECT * FROM highs_create_constraints('datacenter_model', 'demand_D3', 1.0, 1.0);

-- Demand location D4: x_DC1_D4 + x_DC2_D4 + x_DC3_D4 = 1
SELECT * FROM highs_create_constraints('datacenter_model', 'demand_D4', 1.0, 1.0);

-- Constraint 2: Data center capacity constraints
-- For each data center i: sum of assignments <= capacity * z_i
-- Capacity of each data center: DC1=3, DC2=2, DC3=3

-- DC1 capacity: x_DC1_D1 + x_DC1_D2 + x_DC1_D3 + x_DC1_D4 - 3*z_DC1 <= 0
SELECT * FROM highs_create_constraints('datacenter_model', 'capacity_DC1', -1e30, 0.0);

-- DC2 capacity: x_DC2_D1 + x_DC2_D2 + x_DC2_D3 + x_DC2_D4 - 2*z_DC2 <= 0
SELECT * FROM highs_create_constraints('datacenter_model', 'capacity_DC2', -1e30, 0.0);

-- DC3 capacity: x_DC3_D1 + x_DC3_D2 + x_DC3_D3 + x_DC3_D4 - 3*z_DC3 <= 0
SELECT * FROM highs_create_constraints('datacenter_model', 'capacity_DC3', -1e30, 0.0);

-- Constraint 3: Minimum and maximum number of data centers
-- 1 <= z_DC1 + z_DC2 + z_DC3 <= 2 (at least 1, at most 2 data centers)
SELECT * FROM highs_create_constraints('datacenter_model', 'min_datacenters', 1.0, 1e30);
SELECT * FROM highs_create_constraints('datacenter_model', 'max_datacenters', -1e30, 2.0);

-- Step 4: Set constraint coefficients
-- Demand constraints (each demand location assigned to exactly one data center)
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D1', 'x_DC1_D1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D1', 'x_DC2_D1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D1', 'x_DC3_D1', 1.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D2', 'x_DC1_D2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D2', 'x_DC2_D2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D2', 'x_DC3_D2', 1.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D3', 'x_DC1_D3', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D3', 'x_DC2_D3', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D3', 'x_DC3_D3', 1.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D4', 'x_DC1_D4', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D4', 'x_DC2_D4', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'demand_D4', 'x_DC3_D4', 1.0);

-- Capacity constraints
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC1', 'x_DC1_D1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC1', 'x_DC1_D2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC1', 'x_DC1_D3', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC1', 'x_DC1_D4', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC1', 'z_DC1', -3.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC2', 'x_DC2_D1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC2', 'x_DC2_D2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC2', 'x_DC2_D3', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC2', 'x_DC2_D4', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC2', 'z_DC2', -2.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC3', 'x_DC3_D1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC3', 'x_DC3_D2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC3', 'x_DC3_D3', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC3', 'x_DC3_D4', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'capacity_DC3', 'z_DC3', -3.0);

-- Data center count constraints
SELECT * FROM highs_set_coefficients('datacenter_model', 'min_datacenters', 'z_DC1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'min_datacenters', 'z_DC2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'min_datacenters', 'z_DC3', 1.0);

SELECT * FROM highs_set_coefficients('datacenter_model', 'max_datacenters', 'z_DC1', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'max_datacenters', 'z_DC2', 1.0);
SELECT * FROM highs_set_coefficients('datacenter_model', 'max_datacenters', 'z_DC3', 1.0);

-- Step 5: Solve the optimization problem
SELECT * FROM highs_solve('datacenter_model');

-- Expected solution should show:
-- - Which data centers to build (z_DCi = 1)
-- - Assignment of demand locations to data centers (x_DCi_Dj = 1)
-- - Total cost minimized