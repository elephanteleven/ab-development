import { defineConfig } from "cypress";
import baseConfig from "./cypress.config.mjs";

baseConfig.e2e.excludeSpecPattern = ["cypress/e2e/plugins/**/test_cases/*"];
baseConfig.e2e.specPattern = "cypress/e2e/plugins/**/*.js";
export default defineConfig(baseConfig);
