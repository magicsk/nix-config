{
  inputs,
  ...
}:
{
  age = {
    identityPaths = [
      "/persist/ssh/ssh_host_ed25519_key"
      "/home/magic_sk/.ssh/magic_sk"
    ];
    secrets = {
      hashedUserPassword.file = "${inputs.secrets}/hashedUserPassword.age";
      sambaPassword.file = "${inputs.secrets}/sambaPassword.age";
      cloudflareDnsApiCredentials.file = "${inputs.secrets}/cloudflareDnsApiCredentials.age";
    };
  };
}
