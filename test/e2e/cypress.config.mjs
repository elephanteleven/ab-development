import { defineConfig } from "cypress";

export default defineConfig({
   defaultCommandTimeout: 12000,
   responseTimeout: 60000,
   video: false,
   e2e: {
      // testIsolation: false,
      setupNodeEvents(/* on, config */) {
         // implement node event listeners here
      },
   },
});
