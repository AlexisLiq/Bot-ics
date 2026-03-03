const { runPowerShellJson } = require("./run-powershell-json");

function startJavaModalWatcher({ timeoutMs, pollMs }) {
  return runPowerShellJson({
    scriptRelativePath: "scripts/watch-java-modals.ps1",
    params: {
      TimeoutMs: timeoutMs,
      PollMs: pollMs
    },
    requireSummaryOk: false,
    windowsHide: true
  });
}

module.exports = { startJavaModalWatcher };
