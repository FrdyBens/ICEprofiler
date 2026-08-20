namespace Sevelr.Diagnostics;

public interface IDoctorService
{
    Task<List<DiagnosticCheckResult>> RunDiagnosticsAsync(string projectId);
}
