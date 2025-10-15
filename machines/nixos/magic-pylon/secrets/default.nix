{ inputs, ... }:
{
  age.secrets = {
    paperlessPassword.file = "${inputs.secrets}/paperlessPassword.age";
    nextcloudAdminPassword.file = "${inputs.secrets}/nextcloudAdminPassword.age";
    codeServerPassword.file = "${inputs.secrets}/codeServerPassword.age";
    codeServerSudoPassword.file = "${inputs.secrets}/codeServerSudoPassword.age";
    resticPassword = {
      file = "${inputs.secrets}/resticPassword.age";
      /* owner = "restic"; */
    };
  };
}
