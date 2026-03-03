const path = require("node:path");
const { parseSelectorList } = require("./config-helpers");

const DEFAULT_USERNAME_SELECTORS = [
  'input[id="j_id_f:username"]',
  'input[name*="user" i]',
  'input[id*="user" i]',
  'input[name*="login" i]',
  'input[id*="login" i]',
  'input[type="text"]'
];

const DEFAULT_PASSWORD_SELECTORS = [
  'input[id="fscpassword_j_id_f:password"]',
  'input[name*="pass" i]',
  'input[id*="pass" i]',
  'input[type="password"]'
];

const DEFAULT_SUBMIT_SELECTORS = [
  'button[id="j_id_f:BtnLogin"]',
  'button[type="submit"]',
  'input[type="submit"]',
  'button:has-text("Ingresar")',
  'button:has-text("Acceder")',
  'button:has-text("Login")',
  'input[value*="Ingres"]',
  'input[value*="Acced"]',
  'input[value*="Login"]'
];

function resolveStoragePaths(env = process.env, cwd = process.cwd()) {
  return {
    sessionStatePath: path.resolve(cwd, env.SESSION_STATE_PATH || "storage/session.json"),
    jnlpOutputPath: path.resolve(cwd, env.ICS_JNLP_OUTPUT_PATH || "storage/iCS.jnlp")
  };
}

function resolvePathSelectorConfig(env = process.env, cwd = process.cwd()) {
  return {
    ...resolveStoragePaths(env, cwd),
    usernameSelectors: parseSelectorList(env.ICS_USERNAME_SELECTORS, DEFAULT_USERNAME_SELECTORS),
    passwordSelectors: parseSelectorList(env.ICS_PASSWORD_SELECTORS, DEFAULT_PASSWORD_SELECTORS),
    submitSelectors: parseSelectorList(env.ICS_SUBMIT_SELECTORS, DEFAULT_SUBMIT_SELECTORS)
  };
}

module.exports = {
  resolvePathSelectorConfig
};
