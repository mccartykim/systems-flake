# Plasma power settings: idle auto-suspend plus a session that comes up locked.
#
# Why these live here rather than in the NixOS config: PowerDevil (Plasma's
# power daemon) reads per-user files under ~/.config, and Plasma 6 stores its
# power settings in powerdevilrc. Home-manager lets us declare them
# reproducibly instead of hand-editing the file, which Plasma would otherwise
# rewrite on every settings change.
#
# Config schema verified against the installed packages, not from memory:
#   powerdevil 6.8.3  PowerDevilProfileSettings.kcfg
#                     -> groups are [ProfileId][SuspendAndShutdown],
#                        where ProfileId is AC / Battery / LowBattery
#   powerdevil 6.8.3  daemon/powerdevilenums.h
#                     -> PowerButtonAction::Sleep = 1
#                        SleepMode::SuspendToRam = 1
#   powerdevil 6.8.3  daemon/powerdevilsettingsdefaults.cpp
#                     -> default AC idle timeout is 900 s; default action is Sleep
#   kscreenlocker 6.8.3  kscreenlockersettings.kcfg
#                     -> Timeout is a Double measured in MINUTES (default 5)
#                        LockOnStart is a Bool (default false)
#                        LockOnResume is a Bool (default true)
{
  config,
  lib,
  ...
}: {
  xdg.configFile."powerdevilrc".text = ''
    [AC][SuspendAndShutdown]
    AutoSuspendAction=1
    AutoSuspendIdleTimeoutSec=1800
    SleepMode=1

    [Battery][SuspendAndShutdown]
    AutoSuspendAction=1
    AutoSuspendIdleTimeoutSec=600
    SleepMode=1

    [LowBattery][SuspendAndShutdown]
    AutoSuspendAction=1
    AutoSuspendIdleTimeoutSec=300
    SleepMode=1

    [BatteryManagement]
    BatteryCriticalAction=1

    # Plasma 6 tracks "activities" (named desktops). A per-activity inhibit
    # overrides the idle timers above, so a stale entry here silently stops the
    # machine from ever suspending. This activity previously carried
    # InhibitSuspend=true, which would have blocked the AutoSuspendAction
    # settings above, so it is cleared explicitly.
    [Activities][a4bcd836-fffb-47e8-8286-376b32f568b6]
    InhibitScreenManagement=false
    InhibitSuspend=false
  '';

  # Lock the session when the desktop starts.
  #
  # Autologin stays enabled (see hosts/total-eclipse/configuration.nix): Sunshine
  # captures an existing desktop session, so with only a login prompt there is
  # no session to stream. Locking at startup keeps the session available for
  # streaming while leaving the screen secured if someone walks up to it.
  #
  # LockOnStart is the setting that does this. Timeout is unrelated: it is the
  # idle delay before locking, measured in minutes, and is kept at the value
  # already in use (30).
  xdg.configFile."kscreenlockerrc".text = ''
    [$Version]
    update_info=kscreenlocker.upd:0.1-autolock

    [Daemon]
    Timeout=30
    Autolock=true
    LockOnStart=true
    LockOnResume=true
    RequirePassword=true
  '';
}
