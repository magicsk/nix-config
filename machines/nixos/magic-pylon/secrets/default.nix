{ inputs, ... }:
{
  age.secrets = {
    paperlessPassword.file = "${inputs.secrets}/paperlessPassword.age";
    nextcloudAdminPassword.file = "${inputs.secrets}/nextcloudAdminPassword.age";
    resticPassword = {
      file = "${inputs.secrets}/resticPassword.age";
      /* owner = "restic"; */
    };
  };
}
