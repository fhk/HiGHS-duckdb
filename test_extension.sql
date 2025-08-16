-- Test script to verify HiGHS extension loads and basic functions work

-- Load the extension from build directory
LOAD '/workspace/build/release/extension/highs/highs.duckdb_extension';

-- Test basic functions
SELECT highs_version('Test');
SELECT highs_openssl_version('Test');

-- Test table functions (these should return placeholder results for now)
SELECT * FROM highs_create_variables('test_model', 'x', 0.0, 10.0, 1.0, 'continuous');
SELECT * FROM highs_create_constraints('test_model', 'c1', 0.0, 5.0);
SELECT * FROM highs_set_coefficients('test_model', 'c1', 'x', 1.0);
SELECT * FROM highs_solve('test_model');