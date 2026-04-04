{ inputs, ... }:
{
  age.secrets = {
    paperlessPassword.file = "${inputs.secrets}/paperlessPassword.age";
    nextcloudAdminPassword.file = "${inputs.secrets}/nextcloudAdminPassword.age";
    codeServerPassword.file = "${inputs.secrets}/codeServerPassword.age";
    codeServerSudoPassword.file = "${inputs.secrets}/codeServerSudoPassword.age";
    githubPackagesToken.file = "${inputs.secrets}/githubPackagesToken.age";
    tailscaleAuthKey.file = "${inputs.secrets}/tailscaleAuthKey.age";
    traktClientId.file = "${inputs.secrets}/traktClientId.age";
    traktClientSecret.file = "${inputs.secrets}/traktClientSecret.age";
  };
}
