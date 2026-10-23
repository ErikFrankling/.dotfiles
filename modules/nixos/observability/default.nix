# Ships this machine's logs and metrics to the homelab observability stack
# (homelab repo, docs/observability.md) with Grafana Alloy:
#
# - every journald entry (system and user units) as OpenTelemetry logs, with
#   `service.name` = the unit the entry is about, so a failing timer or an
#   error from local-stt or T3 Code becomes an alert there;
# - host metrics (node exporter, including systemd unit states);
# - per-process history: RAM, CPU and disk per (command, cgroup) every 15 s,
#   so a past spike can be traced to a program and its unit or T3 thread;
# - probes of services that only listen on localhost (`probe` label);
# - an OTLP receiver on 127.0.0.1:4317/4318 for programs that speak it
#   (T3 Code, local-stt, Time).
#
# Everything leaves through one OTLP/HTTP exporter to
# https://otlp.erikfrankling.duckdns.org with the bearer token from
# secrets/observability.yaml. Its queue is kept on disk, so the laptop
# catches up after it has been away or asleep.
{
  config,
  lib,
  ...
}:

let
  cfg = config.observability;
  host = config.networking.hostName;

  probes =
    lib.optionalAttrs (config.services.local-stt.enable or false) {
      # The deep check: fails while dictation would not work end to end.
      local-stt = "http://127.0.0.1:8781/health/deep";
    }
    // lib.optionalAttrs config.services.llama-swap.enable {
      llama-swap = "http://127.0.0.1:8000/health";
    }
    // cfg.probes;

  probeTargets = lib.concatStrings (
    lib.mapAttrsToList (name: url: ''
      target {
        name    = "${name}"
        address = "${url}"
        module  = "http_2xx"
        labels  = { probe = "${name}" }
      }
    '') probes
  );

  # journald PRIORITY -> OpenTelemetry severity, so Loki's detected_level works.
  severity = lib.concatStrings (
    lib.mapAttrsToList
      (prio: s: ''
        "set(log.severity_number, SEVERITY_NUMBER_${s}) where log.attributes[\"priority\"] == \"${prio}\"",
        "set(log.severity_text, \"${s}\") where log.attributes[\"priority\"] == \"${prio}\"",
      '')
      {
        "0" = "FATAL";
        "1" = "FATAL";
        "2" = "FATAL";
        "3" = "ERROR";
        "4" = "WARN";
        "5" = "INFO";
        "6" = "INFO";
        "7" = "DEBUG";
      }
  );
in
{
  options.observability = {
    enable = lib.mkEnableOption "shipping logs and metrics to the homelab (Grafana Alloy)";
    probes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        time-agent = "http://127.0.0.1:5600/health";
      };
      description = ''
        Localhost-only health endpoints to probe, by short service name (the
        `probe` label). local-stt and llama-swap are added automatically when
        they are enabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.otlp-ingest-token.sopsFile = ../../../secrets/observability.yaml;
    sops.templates."alloy.env".content = ''
      OTLP_TOKEN=${config.sops.placeholder.otlp-ingest-token}
    '';

    services.alloy = {
      enable = true;
      environmentFile = config.sops.templates."alloy.env".path;
      extraFlags = [
        "--server.http.listen-addr=127.0.0.1:12345"
        "--disable-reporting"
        # otelcol.storage.file (the disk-backed queue) is public preview.
        "--stability.level=public-preview"
      ];
    };
    systemd.services.alloy = {
      restartTriggers = [ config.sops.templates."alloy.env".path ];
      # Logs go to the same journal it reads; keep it from echoing itself.
      serviceConfig.LogLevelMax = "notice";
      # The process exporter reads every process' smaps_rollup (PSS, the fair
      # share of browser memory) and io counters; both need ptrace-read.
      serviceConfig.AmbientCapabilities = [ "CAP_SYS_PTRACE" ];
    };

    environment.etc."alloy/config.alloy".text = ''
      // ---- export: one OTLP/HTTP exporter, queue on disk -------------------
      otelcol.storage.file "queue" { }

      otelcol.auth.bearer "ingest" {
        token = sys.env("OTLP_TOKEN")
      }

      otelcol.exporter.otlphttp "ingest" {
        client {
          endpoint    = "https://otlp.erikfrankling.duckdns.org"
          auth        = otelcol.auth.bearer.ingest.handler
          compression = "gzip"
        }
        sending_queue {
          enabled    = true
          queue_size = 20000
          storage    = otelcol.storage.file.queue.handler
        }
        retry_on_failure {
          enabled          = true
          max_interval     = "5m"
          // Keep retrying for as long as the laptop is away.
          max_elapsed_time = "0s"
        }
      }

      otelcol.processor.batch "out" {
        output {
          logs    = [otelcol.exporter.otlphttp.ingest.input]
          metrics = [otelcol.exporter.otlphttp.ingest.input]
        }
      }

      // Every signal gets host.name; metrics also carry it as the data point
      // label host_name, so Prometheus alerts can group by machine.
      otelcol.processor.transform "host" {
        error_mode = "ignore"
        log_statements {
          context    = "resource"
          statements = ["set(resource.attributes[\"host.name\"], \"${host}\") where resource.attributes[\"host.name\"] == nil"]
        }
        metric_statements {
          context    = "resource"
          statements = ["set(resource.attributes[\"host.name\"], \"${host}\") where resource.attributes[\"host.name\"] == nil"]
        }
        metric_statements {
          context    = "datapoint"
          statements = ["set(datapoint.attributes[\"host_name\"], resource.attributes[\"host.name\"])"]
        }
        output {
          logs    = [otelcol.processor.batch.out.input]
          metrics = [otelcol.processor.batch.out.input]
        }
      }

      // ---- programs that speak OTLP (T3 Code, local-stt, Time) ------------
      otelcol.receiver.otlp "local" {
        grpc { endpoint = "127.0.0.1:4317" }
        http { endpoint = "127.0.0.1:4318" }
        output {
          logs    = [otelcol.processor.transform.host.input]
          metrics = [otelcol.processor.transform.host.input]
        }
      }

      // ---- journald: system and user units --------------------------------
      // service_name = the unit an entry is about: the manager's own
      // messages ("Failed with result ...") name it in UNIT/USER_UNIT, a
      // process' output in _SYSTEMD_UNIT/_SYSTEMD_USER_UNIT. Later rules win;
      // every rule needs a non-empty match, or it would clear the label.
      // service_name becomes a Loki index label, so scope ids are cut off
      // (t3code-claude-14825148.scope -> t3code-claude, session-4.scope ->
      // session). unit/user_unit stay exact; they end up as structured
      // metadata, not labels.
      loki.relabel "journal" {
        forward_to = []
        // Debug output only; nothing alerts on it and it is most of the volume.
        rule {
          source_labels = ["__journal_priority"]
          regex         = "7"
          action        = "drop"
        }
        rule {
          source_labels = ["__journal_syslog_identifier"]
          regex         = "(.+)"
          target_label  = "__tmp_unit"
        }
        rule {
          source_labels = ["__journal__systemd_unit"]
          regex         = "(.+)"
          target_label  = "__tmp_unit"
        }
        rule {
          source_labels = ["__journal__systemd_user_unit"]
          regex         = "(.+)"
          target_label  = "__tmp_unit"
        }
        rule {
          source_labels = ["__journal_unit"]
          regex         = "(.+)"
          target_label  = "__tmp_unit"
        }
        rule {
          source_labels = ["__journal_user_unit"]
          regex         = "(.+)"
          target_label  = "__tmp_unit"
        }
        rule {
          source_labels = ["__tmp_unit"]
          regex         = "(.+)"
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__tmp_unit"]
          regex         = "(.+?)\\.service"
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__tmp_unit"]
          regex         = "(.+?)(?:-[0-9a-f]{6,}|-[0-9]+)?\\.scope"
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__journal__systemd_unit"]
          regex         = "(.+)"
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal_unit"]
          regex         = "(.+)"
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal__systemd_user_unit"]
          regex         = "(.+)"
          target_label  = "user_unit"
        }
        rule {
          source_labels = ["__journal_user_unit"]
          regex         = "(.+)"
          target_label  = "user_unit"
        }
        rule {
          source_labels = ["__journal_priority"]
          regex         = "(.+)"
          target_label  = "priority"
        }
      }

      loki.source.journal "journal" {
        max_age       = "12h"
        relabel_rules = loki.relabel.journal.rules
        forward_to    = [loki.process.journal.receiver]
      }

      // Cloudflare WARP logs its DEBUG lines at info priority, thousands a day.
      loki.process "journal" {
        stage.match {
          selector = "{service_name=\"cloudflare-warp\"}"
          stage.drop {
            expression = " DEBUG "
          }
        }
        forward_to = [otelcol.receiver.loki.journal.receiver]
      }

      otelcol.receiver.loki "journal" {
        output {
          logs = [otelcol.processor.transform.journal.input]
        }
      }

      otelcol.processor.transform "journal" {
        error_mode = "ignore"
        log_statements {
          context    = "log"
          statements = [
            ${severity}
            "set(log.attributes[\"service.name\"], log.attributes[\"service_name\"])",
            "delete_key(log.attributes, \"service_name\")",
            "delete_key(log.attributes, \"job\")",
            "delete_key(log.attributes, \"loki.attribute.labels\")",
          ]
        }
        output {
          logs = [otelcol.processor.batch.journal.input]
        }
      }

      otelcol.processor.batch "journal" {
        output {
          logs = [otelcol.processor.groupbyattrs.journal.input]
        }
      }

      // Moves service.name from each record to its resource, grouping a
      // batch's records of the same unit together.
      otelcol.processor.groupbyattrs "journal" {
        keys = ["service.name"]
        output {
          logs = [otelcol.processor.transform.host.input]
        }
      }

      // ---- metrics: host and localhost-only services ------------------------
      prometheus.exporter.unix "host" {
        enable_collectors = ["systemd"]
        systemd {
          unit_include = ".+\\.service"
        }
      }

      prometheus.exporter.blackbox "local" {
        config = "{ modules: { http_2xx: { prober: http, timeout: 5s } } }"
        ${probeTargets}
      }

      prometheus.scrape "local" {
        targets         = array.concat(prometheus.exporter.unix.host.targets, prometheus.exporter.blackbox.local.targets)
        scrape_interval = "60s"
        forward_to      = [otelcol.receiver.prometheus.local.receiver]
      }

      otelcol.receiver.prometheus "local" {
        output {
          metrics = [otelcol.processor.transform.host.input]
        }
      }

      // ---- per-process history: a task manager you can scroll back --------
      // process-exporter, built into Alloy: one group per (command, cgroup),
      // so `namedprocess_namegroup_*{groupname="cc1plus", unit="t3code-claude-
      // fc888130.scope"}` says which program in which unit (T3 thread scope,
      // app, service) used the RAM, CPU and disk at any past time. Kernel
      // threads (root cgroup) are dropped; host totals cover them.
      // Queries: the system-history skill (modules/home-manager/auto-update).
      prometheus.exporter.process "procs" {
        track_threads       = false
        recheck_on_scrape   = true
        remove_empty_groups = true
        matcher {
          name    = "{{.Comm}}|{{.Cgroups}}"
          cmdline = [".*"]
        }
      }

      prometheus.scrape "procs" {
        targets         = prometheus.exporter.process.procs.targets
        scrape_interval = "15s"
        forward_to      = [prometheus.relabel.procs.receiver]
      }

      prometheus.relabel "procs" {
        forward_to = [otelcol.receiver.prometheus.local.receiver]
        rule {
          source_labels = ["__name__"]
          regex         = "namedprocess_namegroup_(cpu_seconds_total|memory_bytes|read_bytes_total|write_bytes_total|major_page_faults_total|num_procs|num_threads|oldest_start_time_seconds)"
          action        = "keep"
        }
        rule {
          source_labels = ["memtype"]
          regex         = "virtual|proportionalSwapped"
          action        = "drop"
        }
        // groupname = "comm|[<cgroup v1 path> <cgroup v2 path>]"; keep the last.
        rule {
          source_labels = ["groupname"]
          regex         = ".*[ \\[]([^ \\[\\]]*)\\]"
          target_label  = "cgroup"
        }
        rule {
          source_labels = ["cgroup"]
          regex         = "/?"
          action        = "drop"
        }
        rule {
          source_labels = ["cgroup"]
          regex         = ".*/([^/]+)"
          target_label  = "unit"
        }
        rule {
          source_labels = ["groupname"]
          regex         = "([^|]*)\\|.*"
          target_label  = "groupname"
        }
      }
    '';

    # The same history at 5 s resolution, kept on this machine for a week:
    # `below replay -t "10 min ago"` is top/htop scrolled back in time, with
    # the cgroup tree (T3 thread scopes, apps) and every process. Also records
    # processes that lived between two samples (eBPF exit stats).
    services.below = {
      enable = true;
      compression.enable = true;
      collect.ioStats = true;
      retention = {
        time = 7 * 24 * 3600;
        size = 4 * 1024 * 1024 * 1024;
      };
    };
  };
}
