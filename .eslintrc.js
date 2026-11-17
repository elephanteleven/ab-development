module.exports = {
   env: {
      node: true,
      browser: true,
      es6: true,
   },

   parserOptions: {
      ecmaVersion: 2020,
      sourceType: "module",
   },

   // "parser": "babel-eslint",
   extends: ["eslint:recommended", "prettier", "plugin:cypress/recommended"], // extending recommended config and config derived from eslint-config-prettier

   globals: {
      webix: "readonly",
      $$: "readonly",
   },

   plugins: ["prettier", "cypress"],
   rules: {
      "prettier/prettier": [
         // customizing prettier rules (unfortunately not many of them are customizable)
         "error",
         {
            arrowParens: "always",
            endOfLine: "lf",
            printWidth: 80,
            tabWidth: 3,
         },
      ],
      "no-console": 0, // "off",
      // eqeqeq: ["error", "always"] // adding some custom ESLint rules
   },
};
