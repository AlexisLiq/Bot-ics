const path = require("node:path");
const { spawn } = require("node:child_process");
const { config } = require("../config/config");

function buildPowerShellArgs(scriptPath, params = {}) {
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];

  for (const [name, rawValue] of Object.entries(params)) {
    if (rawValue === undefined || rawValue === null) continue;
    args.push(`-${name}`, String(rawValue));
  }

  return args;
}

function runPowerShellJson({
  scriptRelativePath,
  params,
  requireSummaryOk = true,
  windowsHide = true,
  timeoutMs
}) {
  const globalTimeoutMs = Number(config.icsPowerShellTimeoutMs || 15000);
  const scriptTimeoutMs = Number(params?.TimeoutMs);
  const hasExplicitTimeout = Number.isFinite(timeoutMs) && timeoutMs > 0;
  const effectiveTimeoutMs = hasExplicitTimeout
    ? Number(timeoutMs)
    : (
      Number.isFinite(scriptTimeoutMs) && scriptTimeoutMs > 0
        ? Math.max(globalTimeoutMs, scriptTimeoutMs + 5000)
        : globalTimeoutMs
    );

  const scriptPath = path.resolve(process.cwd(), scriptRelativePath);
  const args = buildPowerShellArgs(scriptPath, params);

  const child = spawn("powershell.exe", args, {
    windowsHide,
    stdio: ["ignore", "pipe", "pipe"]
  });

  let stdout = "";
  let stderr = "";

  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });

  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  const result = new Promise((resolve) => {
    let settled = false;
    let timeoutId = null;

    const settle = (payload) => {
      if (settled) return;
      settled = true;
      if (timeoutId) clearTimeout(timeoutId);
      resolve(payload);
    };

    if (Number.isFinite(effectiveTimeoutMs) && effectiveTimeoutMs > 0) {
      timeoutId = setTimeout(() => {
        try {
          child.kill("SIGTERM");
        } catch {
          // no-op
        }

        const timeoutText = `PowerShell timeout after ${effectiveTimeoutMs} ms (${scriptRelativePath}).`;
        settle({
          ok: false,
          exitCode: null,
          timedOut: true,
          stderr: timeoutText,
          rawStdout: stdout.trim(),
          summary: { ok: false, error: timeoutText }
        });
      }, effectiveTimeoutMs);
    }

    child.once("error", (error) => {
      settle({
        ok: false,
        error: error.message
      });
    });

    child.once("close", (code) => {
      const rawStdout = stdout.trim();
      const stdErrText = stderr.trim();

      let parsed = null;
      if (rawStdout) {
        try {
          parsed = JSON.parse(rawStdout);
        } catch {
          parsed = null;
        }
      }

      const summaryOk = !requireSummaryOk || !!parsed?.ok;
      settle({
        ok: code === 0 && summaryOk,
        exitCode: code,
        stderr: stdErrText,
        rawStdout,
        summary: parsed
      });
    });
  });

  return { child, result };
}

module.exports = { runPowerShellJson };
