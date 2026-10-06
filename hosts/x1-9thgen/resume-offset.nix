{ ... }:

{
  # Generated for the currently installed Btrfs swapfile; regenerate after a
  # Disko reformat because the physical resume offset is filesystem-specific.
  boot.kernelParams = [ "resume_offset=533760" ];
}
