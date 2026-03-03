const { runLoginFlow } = require("./core/login");

runLoginFlow()
  .then((result) => {
    console.log("\nLogin completado.");
    console.log(`URL final: ${result.finalUrl}`);
    console.log(`Sesion guardada en: ${result.sessionStatePath}`);
  })
  .catch((error) => {
    console.error("\nError en el flujo de login:");
    console.error(error.message);
    if (error.cause) {
      console.error("Causa:", error.cause.message || error.cause);
    }
    process.exitCode = 1;
  });
