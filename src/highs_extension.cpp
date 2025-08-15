#define DUCKDB_EXTENSION_MAIN

#include "highs_extension.hpp"
#include "duckdb.hpp"
#include "duckdb/common/exception.hpp"
#include "duckdb/common/string_util.hpp"
#include "duckdb/function/scalar_function.hpp"
#include "duckdb/main/extension_util.hpp"
#include <duckdb/parser/parsed_data/create_scalar_function_info.hpp>

// OpenSSL linked through vcpkg
#include <openssl/opensslv.h>

// HiGHS headers
#include "Highs.h"

namespace duckdb {

inline void HighsVersionScalarFun(DataChunk &args, ExpressionState &state, Vector &result) {
	auto &name_vector = args.data[0];
	UnaryExecutor::Execute<string_t, string_t>(name_vector, result, args.size(), [&](string_t name) {
		return StringVector::AddString(result, "Hello " + name.GetString() + ", HiGHS version: " + highsVersion());
	});
}

inline void HighsOpenSSLVersionScalarFun(DataChunk &args, ExpressionState &state, Vector &result) {
	auto &name_vector = args.data[0];
	UnaryExecutor::Execute<string_t, string_t>(name_vector, result, args.size(), [&](string_t name) {
		return StringVector::AddString(result, "Hello " + name.GetString() + ", HiGHS version: " + highsVersion() + 
		                                           ", OpenSSL version: " + OPENSSL_VERSION_TEXT);
	});
}

static void LoadInternal(DatabaseInstance &instance) {
	// Register HiGHS version function
	auto highs_version_function = ScalarFunction("highs_version", {LogicalType::VARCHAR}, LogicalType::VARCHAR, HighsVersionScalarFun);
	ExtensionUtil::RegisterFunction(instance, highs_version_function);

	// Register HiGHS with OpenSSL version function
	auto highs_openssl_version_function = ScalarFunction("highs_openssl_version", {LogicalType::VARCHAR},
	                                                      LogicalType::VARCHAR, HighsOpenSSLVersionScalarFun);
	ExtensionUtil::RegisterFunction(instance, highs_openssl_version_function);
}

void HighsExtension::Load(DuckDB &db) {
	LoadInternal(*db.instance);
}
std::string HighsExtension::Name() {
	return "highs";
}

std::string HighsExtension::Version() const {
#ifdef EXT_VERSION_HIGHS
	return EXT_VERSION_HIGHS;
#else
	return "";
#endif
}

} // namespace duckdb

extern "C" {

DUCKDB_EXTENSION_API void highs_init(duckdb::DatabaseInstance &db) {
	duckdb::DuckDB db_wrapper(db);
	db_wrapper.LoadExtension<duckdb::HighsExtension>();
}

DUCKDB_EXTENSION_API const char *highs_version() {
	return duckdb::DuckDB::LibraryVersion();
}
}

#ifndef DUCKDB_EXTENSION_MAIN
#error DUCKDB_EXTENSION_MAIN not defined
#endif
