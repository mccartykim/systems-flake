# email-digest STUB (a3j.6 6b interim): the service moved to historian, but
# the email-digest USER + GROUP must survive on this host until the a3j.7
# organisms domU moves the Interrogator. Two reasons:
#   1. vox-organism's extraGroups includes "email-digest" (roster
#      daemonExtraGroups) — deleting the group breaks user activation.
#   2. The Interrogator (#53) still reads this host's OLD xapian index at
#      /var/lib/email-digest/.cache/mu — now FROZEN (no mbsync feeds it),
#      read-only, degrading benignly (stale mail context) until the domU
#      era repoints it at historian's live index.
# Delete this file + the mu package reference when the organisms move.
{
  users.users.email-digest = {
    isSystemUser = true;
    group = "email-digest";
    home = "/var/lib/email-digest";
  };
  users.groups.email-digest = {};
}
