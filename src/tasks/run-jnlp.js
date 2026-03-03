const fs = require("node:fs/promises");
const { spawn, execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { config } = require("../config/config");
const { startJavaModalWatcher } = require("../windows/java-modal-watcher");

const execFileAsync = promisify(execFile);

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function resolveLauncher(command) {
  try {
    const { stdout } = await execFileAsync("where.exe", [command], { windowsHide: true });
    const firstMatch = stdout
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find(Boolean);
    return firstMatch || command;
  } catch {
    return command;
  }
}

async function listProcesses() {
  const psScript = [
    "$ErrorActionPreference = 'SilentlyContinue'",
    "$p = Get-Process | Select-Object Id, ProcessName, MainWindowTitle",
    "$p | ConvertTo-Json -Depth 3 -Compress"
  ].join("; ");

  const { stdout } = await execFileAsync(
    "powershell.exe",
    ["-NoProfile", "-Command", psScript],
    { windowsHide: true, maxBuffer: 10 * 1024 * 1024 }
  );

  const trimmed = stdout.trim();
  if (!trimmed) return [];

  const sanitized = trimmed.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "");
  const parsed = JSON.parse(sanitized);
  const arr = Array.isArray(parsed) ? parsed : [parsed];
  return arr.map((item) => ({
    id: Number(item.Id),
    processName: String(item.ProcessName || ""),
    mainWindowTitle: String(item.MainWindowTitle || "")
  }));
}

function summarizeMatches(processes, hints) {
  const loweredHints = hints.map((h) => h.toLowerCase());

  return processes.filter((proc) => {
    const name = proc.processName.toLowerCase();
    const title = proc.mainWindowTitle.toLowerCase();
    return loweredHints.some((hint) => name.includes(hint) || title.includes(hint));
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function resolveJavaWatcher(javaModalWatcher) {
  if (!javaModalWatcher) return null;
  try {
    return await javaModalWatcher.result;
  } catch (error) {
    return {
      ok: false,
      error: error.message
    };
  }
}

async function waitForClientLaunch(beforeProcesses, timeoutMs, hints) {
  const beforeIds = new Set(beforeProcesses.map((p) => p.id));
  const startedAt = Date.now();
  let lastSnapshot = [];

  while (Date.now() - startedAt < timeoutMs) {
    lastSnapshot = await listProcesses();
    const newProcesses = lastSnapshot.filter((p) => !beforeIds.has(p.id));
    const hintedNewProcesses = summarizeMatches(newProcesses, hints);

    const strongMatch = hintedNewProcesses.find(
      (p) =>
        /ics[_-]?client/i.test(p.processName) ||
        /internet collection|ics/i.test(p.mainWindowTitle)
    );

    if (strongMatch) {
      return {
        status: "client_detected",
        matchedProcesses: hintedNewProcesses,
        strongMatch
      };
    }

    if (hintedNewProcesses.length > 0) {
      return {
        status: "launcher_detected",
        matchedProcesses: hintedNewProcesses,
        strongMatch: null
      };
    }

    await sleep(1000);
  }

  return {
    status: "not_detected",
    matchedProcesses: summarizeMatches(lastSnapshot, hints),
    strongMatch: null
  };
}

async function runJnlpTask(options = {}) {
  const jnlpPath = options.jnlpPath || config.jnlpOutputPath;

  if (!(await fileExists(jnlpPath))) {
    throw new Error(`No existe el archivo JNLP en ${jnlpPath}.`);
  }

  const launcher = await resolveLauncher(config.jnlpLauncher);
  const beforeProcesses = await listProcesses();
  let javaModalWatcher = null;

  if (config.handleJavaModals) {
    javaModalWatcher = startJavaModalWatcher({
      timeoutMs: config.javaModalWatchTimeoutMs,
      pollMs: config.javaModalPollMs
    });
  }

  console.log(`Lanzando JNLP con: ${launcher}`);
  console.log(`Archivo: ${jnlpPath}`);

  const child = spawn(launcher, [jnlpPath], {
    windowsHide: false,
    detached: true,
    stdio: "ignore"
  });
  child.unref();

  const validation = await waitForClientLaunch(
    beforeProcesses,
    config.jnlpLaunchTimeoutMs,
    config.clientProcessHints
  );

  const javaModalHandling = await resolveJavaWatcher(javaModalWatcher);

  return {
    launcher,
    jnlpPath,
    launcherPid: child.pid || null,
    validation,
    javaModalHandling
  };
}

module.exports = { runJnlpTask };
