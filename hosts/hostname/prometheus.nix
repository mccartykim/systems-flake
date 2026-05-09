diff --git a/hosts/hostname/prometheus.nix b/hosts/hostname/prometheus.nix
index 1234567..89abcde 100644
--- a/hosts/hostname/prometheus.nix
+++ b/hosts/hostname/prometheus.nix
@@ -15,6 +15,12 @@ services.prometheus = {
   config = {
     global = {
       scrape_interval = "15s"
+    }
+  silences = {
+    rules = [
+      {
+        name = "silence-test"
+        duration = "1d"
+        matches = [ "alertname = "SilenceTest"" ]
+      }
+    ]
   }
 }
}