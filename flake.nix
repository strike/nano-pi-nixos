{
  description = "NixOS for Friendlyelec NanoPi R5C";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs, flake-utils }: ({
    nixosConfigurations.nano-pi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ({ config, lib, pkgs, ... }: {
          hardware.deviceTree.name = "rockchip/rk3568-nanopi-r5c.dtb";
          hardware.firmware = [ pkgs.firmwareLinuxNonfree ];
          hardware.enableRedistributableFirmware = true;
          hardware.enableAllFirmware = true;
          powerManagement.cpuFreqGovernor = "schedutil";

          boot = {
            loader = {
              grub.enable = false;
              generic-extlinux-compatible = {
                enable = true;
                useGenerationDeviceTree = true;
              };
            };

            kernelParams = [
              "console=tty1"
              "console=ttyS2,1500000"
              "earlycon=uart8250,mmio32,0xfe660000"
              "ignore_loglevel"
            ];

            initrd.includeDefaultModules = false;

            initrd.availableKernelModules = [
              # Storage
              "sdhci_of_dwcmshc"
              "dw_mmc_rockchip"
            ];

            initrd.postDeviceCommands = ''
              partitionName=$(basename $(readlink -f /dev/disk/by-partlabel/rootfs))
              partitionNumber=$(cat /sys/class/block/$partitionName/partition)
              deviceName=$(basename $(readlink -f /sys/class/block/$partitionName/../))
              deviceSize=$(cat /sys/class/block/$deviceName/size)
              partitionStart=$(cat /sys/class/block/$deviceName/$partitionName/start)
              partitionSize=$(cat /sys/class/block/$deviceName/$partitionName/size)
              parititonEnd=$(($partitionStart + $partitionSize + 33))

              if [ "$deviceSize" -gt "$parititonEnd" ]; then
                echo "Resizing $partitionName to fill whole disk..."
                ${pkgs.gptfdisk}/bin/sgdisk --delete=$partitionNumber /dev/$deviceName
                ${pkgs.gptfdisk}/bin/sgdisk --largest-new=$partitionNumber --change-name=$partitionNumber:rootfs --attributes=$partitionNumber:set:2 /dev/$deviceName
              fi
            '';

            postBootCommands = ''
              if [ -f /nix-path-registration ]; then
                ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration && rm /nix-path-registration
              fi

              ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

              # resize the ext4 image to occupy the full partition
              rootPart=$(readlink -f /dev/disk/by-partlabel/rootfs)
              ${pkgs.e2fsprogs}/bin/resize2fs $rootPart

              # FIXME: move this shit from here to the image population
              if ! [ -e /etc/nixos/flake.nix ]; then
                cp ${./flake.nix} /etc/nixos/flake.nix
                cp ${./linux_config} /etc/nixos/linux_config
                cp ${
                  ./0001-fix-bcmdhd-build.patch
                } /etc/nixos/0001-fix-bcmdhd-build.patch
                cp ${./uboot.nix} /etc/nixos/uboot.nix
                chmod +w /etc/nixos/flake.nix
              fi
            '';
          };

          services = {
            openssh = {
              enable = true;
              openFirewall = false;
              settings = {
                PermitRootLogin = "no";
                PasswordAuthentication = false;
              };
            };
            tailscale.enable = true;
          };

          fileSystems = {
            "/" = { device = "/dev/disk/by-partlabel/rootfs"; };
          };

          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
          nix.registry.nixpkgs.flake = nixpkgs;

          system.build.rootfs =
            pkgs.callPackage "${nixpkgs}/nixos/lib/make-ext4-fs.nix" ({
              storePaths = [ config.system.build.toplevel ];
              compressImage = false;
              # FIXME: generic-extlinux-compatible.populateCmd _copies_ kernel, initrd & dtbs from
              # /nix/store to /boot which is a bit useless since both folders are in same FS
              populateImageCommands = ''
                mkdir -p ./files/boot
                ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
              '';
              volumeLabel = "nixos";
            });

          networking = {
            hostName = "nano-pi";
            useDHCP = false;
            enableIPv6 = false;
            firewall = {
              enable = true;
              interfaces = {
                enP1p1s0.allowedTCPPorts = [ 22 8123 8020 ];
                enP2p1s0.allowedTCPPorts = [ 22 8123 8020 ];
                ${config.services.tailscale.interfaceName}.allowedTCPPorts =
                  [ 22 443 ];
              };
              allowedUDPPorts = [ config.services.tailscale.port ];
            };
          };
          systemd.network = {
            enable = true;
            wait-online.enable = false;
            networks = {
              enP1p1s0 = {
                matchConfig.Name = "enP1p1s0";
                networkConfig.DHCP = "ipv4";
              };
              enP2p1s0 = {
                matchConfig.Name = "enP2p1s0";
                networkConfig.DHCP = "ipv4";
              };
            };
          };

          environment.systemPackages = with pkgs; [
            lsof
            usbutils
            pciutils
            file
            htop
            iotop
            iw
            tcpdump
            vim
            tmux
            git
            lm_sensors
          ];
          nixpkgs.config.allowUnfree = true;
          virtualisation.docker.enable = true;

          security = { sudo.wheelNeedsPassword = false; };

          users = {
            users = {
              root = { password = "123"; };
              astrike = {
                openssh.authorizedKeys.keys = [
                  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCpGMqX/tetOs1Ob4HcC1nuflATq/+KjvF00pMX7b6KS4+Z6dcNoKQawoYO5Hn/AJkNKHSvskA+2oiLsehVyNnBrsdzO4AS+bDwTDUF1OgwLUmhEDr+DNxplfFz9IntWqZ1Tjzwoqv6R3nXfjNCxaciLIyQmWy97LIJyHgelltQcCZpuVvvTQVQ0grxPl4FSx7MqNKk7u/FAcvd2EtoBTFPBP4DCuvScdK/1wpYuCbMSkkVqFbFaNVZ+14+rUGoEjx8nLl3kD3yg2MFkZYHCaii/KAaN/KmDmxBOxHML7pRohbiHtS58pfMDyTJZBEn8i7ZPqpV4n/efqV9KW1TAExgKvCZzAZlMrReOtArvsOwY1GBfN/iihLGsYqTBbNY2i2GFYY9hLAFr2oauytkpj62WoE1HH29oaaS0Ab7958oQzW74ESSGNrL36uOBpAYox3SC0MLLY/VGGH9O8X8OFeyglYRVMHHWlxAgGVI0j+V635AEE4iTpwGnQys2xw/ukFxv+Hb7+OTWK/nG7aY7G+Nhvc+0w3K9VElIMSV6P56rWc9HFbAjFRFdA7fkEuUHrzxLGY2kpoYRdXiJSc4qLpfMy3s8galaFCUtqoi/4MZxvoDdUsuGjDXrqh1gm8w63sVanc4lM/8C8jz96po3OmVmzplaAhmYJAFwwAy3D3CMw== astrike@avride.ai"
                ];
                isNormalUser = true;
                extraGroups = [ "wheel" "docker" ];
              };
            };
          };

          system.stateVersion = "24.05";
        })
      ];
    };
  });
}
