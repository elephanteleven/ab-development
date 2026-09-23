import { defineConfig } from "cypress";
import baseConfig from "./cypress.config.mjs";

baseConfig.e2e.excludeSpecPattern = [
   "cypress/e2e/plugins/**/*",
];
export default defineConfig(baseConfig);
