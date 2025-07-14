{
  pkgs,
  ...
}:
{
  nix.settings.trusted-users = [ "magic_sk" ];

  users = {
    users = {
      magic_sk = {
        shell = pkgs.zsh;
        uid = 1000;
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "users"
          "video"
          "podman"
          "input"
        ];
        group = "magic_sk";
        openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxkIv9JgvCjb8pFZaqcMiT4uCe76HECzmzIZZD3d8XTT+18p8ttmoD+QUJhA4js/xAnwj08rhFikZsKMYOcFbBxkWnxBa0tLBkJghAq9dYqXwvtDrPo13CwxT/RQQY6s6xDMNz3KKX7/fjPm6xIirvg82GeOB1QTb05g8PcsErKcMoymmUfhHVPJo4l7v/IBAvzyeRITj+KmE96WrjAUZjFQYWiu3+zC4C2zYVVzE1mYkUOQQuI46Tnz9rnO6lYtm/u7RF5Lgtuw9dKal6M92P2qUG0ov9QnKpz0defSTuDziE1XijqCp/hfAJCwNu/w01Ul+zxyvDZ2UCIUUl53ini0G5qj4x9a/XVqAzx747i3FgJUpj+2DqzhWH0OhTnblHmlIf7acRNuYH5AMiFw4HjPPEw/d0nyRvfGAxpnjipm0nZ+X63WAnd9Im/xq4Xc1yKt/QfGHsmfx/leCP4YsylnY8eyGmXvUUfIAYJVd50QiCmp72OhpXzCOpoIZGTT7FP4lmhDAfDKU1BihiHVIKWz6kUjRZM0/U0sQJQrUKUVqP2c43WgEVuYbJ8SsP+NTG51/AJSqW0GiBe2tj9jco/l6pyjS+ilYaa0naxXYByjfu8gL/J89JHiChmPy2FaefOha1KqKoEYY7oCCoSEC3DTeH+npZ0BXAxdpXaYkt4w== magicsk@magicsk.eu"
        ];
      };
    };
    groups = {
      magic_sk = {
        gid = 1000;
      };
    };
  };
  programs.zsh.enable = true;

}
