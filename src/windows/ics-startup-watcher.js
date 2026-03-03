const { runPowerShellJson } = require("./run-powershell-json");

function startWaitIcsStartup({
  windowTitleHint,
  timeoutMs,
  pollMs,
  stablePolls
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/wait-ics-startup.ps1",
    params: {
      WindowTitleHint: windowTitleHint,
      TimeoutMs: timeoutMs,
      PollMs: pollMs,
      StablePolls: stablePolls
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startWaitIcsStartup };
