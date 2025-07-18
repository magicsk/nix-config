{
  pkgs,
  config,
  inputs,
  lib,
  ...
}:
{
  home.packages = with pkgs; [ grc ];

  programs = {
    command-not-found.enable = false;
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = [ "--cmd cd" ];
    };
    zsh = {
      enable = true;
      enableCompletion = false;
      zplug = {
        enable = true;
        plugins = [
          { name = "zsh-users/zsh-autosuggestions"; }
          { name = "zsh-users/zsh-syntax-highlighting"; }
          { name = "zsh-users/zsh-completions"; }
          { name = "zsh-users/zsh-history-substring-search"; }
          { name = "unixorn/warhol.plugin.zsh"; }
        ];
      };
      shellAliases = {
        la = "ls --color -lha";
        df = "df -h";
        ipp = "curl ipinfo.io/ip";
        ipp6 = "curl -6 v6.ipinfo.io/ip";
        yh = "yt-dlp --continue --no-check-certificate --format=bestvideo+bestaudio --exec='ffmpeg -i {} -c:a copy -c:v copy {}.mkv && rm {}'";
        yd = "yt-dlp --continue --no-check-certificate --format=bestvideo+bestaudio --exec='ffmpeg -i {} -c:v prores_ks -profile:v 1 -vf fps=25/1 -pix_fmt yuv422p -c:a pcm_s16le {}.mov && rm {}'";
        ya = "yt-dlp --continue --no-check-certificate --format=bestaudio -x --audio-format wav";
        aspm = "sudo lspci -vv | awk '/ASPM/{print $0}' RS= | grep --color -P '(^[a-z0-9:.]+|ASPM )'";
        mkdir = "mkdir -p";
        renix = "sudo nixos-rebuild switch --flake /etc/nixos#magic-pylon";
        testnix = "sudo nixos-rebuild test --flake /etc/nixos#magic-pylon";
        s = "sudo";
        i = "yay -S";
        u = "yay -Sy";
        r = "yay -R";
        f = "ranger";
        v = "nvim";
        vi = "nvim";
        vim = "nvim";
        pl = "pacman -Qv";
        untar = "tar -xvzf";
        zrc = "nano ~/.zshrc";
        t = "date +%s%3N";
        api = "ssh ubuntu@132.226.217.72";
        alumentum = "cd /mnt/Alumentum";
        nitor = "cd /mnt/Nitor";
        tallow = "cd /mnt/Tallow";
        wilson = "cd /mnt/Wilson";
        services = "cd /persist/opt/services/";
      };

      initContent = ''
        # Disable nix command not found handler because of slowdown
        unset -f command_not_found_handler
        # Cycle back in the suggestions menu using Shift+Tab
        bindkey '^[[Z' reverse-menu-complete

        bindkey '^B' autosuggest-toggle
        # Make Ctrl+W remove one path segment instead of the whole path
        WORDCHARS=''${WORDCHARS/\/}

        # Highlight the selected suggestion
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
        zstyle ':completion:*' menu yes=long select

        export EDITOR=nvim || export EDITOR=vim
        export LANG=en_US.UTF-8
        export LC_CTYPE=en_US.UTF-8
        export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

        source $ZPLUG_HOME/repos/unixorn/warhol.plugin.zsh/warhol.plugin.zsh
        bindkey '^[[A' history-substring-search-up
        bindkey '^[[B' history-substring-search-down

        if command -v motd &> /dev/null
        then
          motd
        fi
        bindkey -e
      '';
    };
  };
}
