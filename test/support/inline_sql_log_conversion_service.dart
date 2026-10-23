import 'package:dev_orbit/features/sql_log/sql_log_controller.dart';
import 'package:dev_orbit/features/sql_log/sql_log_converter.dart';

/// Runs the log→SQL conversion on the calling isolate so a pump sees the
/// result. The production controller uses an isolate instead.
class InlineSqlLogConversionService implements SqlLogConversionService {
  const InlineSqlLogConversionService();

  @override
  Future<SqlLogConversionResult> convert(
    String source,
    SqlLogDialect dialect,
  ) async {
    return const SqlLogConverter().convert(source, dialect: dialect);
  }
}
