const { runPowerShellJson } = require("./run-powershell-json");

function startPostSearchGestionar({
  mainWindowHwnd,
  targetProcessName,
  timeoutMs,
  pollMs,
  stepDelayMs
}) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/post-search-gestionar.ps1",
    params: {
      MainWindowHwnd: mainWindowHwnd,
      TargetProcessName: targetProcessName,
      TimeoutMs: timeoutMs,
      PollMs: pollMs,
      StepDelayMs: stepDelayMs
    },
    requireSummaryOk: true,
    windowsHide: true
  });
}

module.exports = { startPostSearchGestionar };
