using System.Security.AccessControl;
using System.Security.Principal;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Filesystem;

public class WindowsAclManager(IAuditLogger logger) : IAclManager
{
    public void RestrictToCurrentUserOnly(string directoryPath, bool failClosed)
    {
        try
        {
            if (!Directory.Exists(directoryPath))
                Directory.CreateDirectory(directoryPath);

            var dirInfo = new DirectoryInfo(directoryPath);
            var dSecurity = dirInfo.GetAccessControl();

            // Disable inheritance and strip inherited rules
            dSecurity.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

            var currentUser = WindowsIdentity.GetCurrent().User
                ?? throw new FilesystemIsolationException("Unable to resolve current Windows user identity.");

            // Clear existing rules
            var currentRules = dSecurity.GetAccessRules(true, false, typeof(SecurityIdentifier));
            foreach (FileSystemAccessRule rule in currentRules)
            {
                dSecurity.RemoveAccessRule(rule);
            }

            var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

            // 1. Current User: FullControl
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                currentUser,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 2. SYSTEM: FullControl (Required by Windows and Chromium service processes)
            var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                systemSid,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 3. Administrators: FullControl
            var adminsSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                adminsSid,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 4. ALL APPLICATION PACKAGES (S-1-15-2-1): Read & Execute (Required for Chromium Sandbox)
            try
            {
                var appPackagesSid = new SecurityIdentifier("S-1-15-2-1");
                dSecurity.AddAccessRule(new FileSystemAccessRule(
                    appPackagesSid,
                    FileSystemRights.ReadAndExecute,
                    inheritance,
                    PropagationFlags.None,
                    AccessControlType.Allow));
            }
            catch { }

            dirInfo.SetAccessControl(dSecurity);
            logger.LogSecurityEvent("SYSTEM", "ACL", directoryPath, "Protect", $"Isolated directory to user {currentUser.Value}");
        }
        catch (Exception ex)
        {
            logger.LogError("SYSTEM", "ACL", $"Failed applying NTFS ACL to {directoryPath}: {ex.Message}");
            if (failClosed)
                throw new FilesystemIsolationException($"Strict mode ACL failure on path '{directoryPath}': {ex.Message}", ex);
        }
    }

    public bool VerifyAccessControl(string directoryPath)
    {
        try
        {
            if (!Directory.Exists(directoryPath)) return false;
            var dirInfo = new DirectoryInfo(directoryPath);
            var dSecurity = dirInfo.GetAccessControl();
            return dSecurity.AreAccessRulesProtected;
        }
        catch
        {
            return false;
        }
    }
}
