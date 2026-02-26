// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************
//
//
// -- This is a parent command --
// Cypress.Commands.add('login', (email, password) => { ... })
//
//
// -- This is a child command --
// Cypress.Commands.add('drag', { prevSubject: 'element'}, (subject, options) => { ... })
//
//
// -- This is a dual command --
// Cypress.Commands.add('dismiss', { prevSubject: 'optional'}, (subject, options) => { ... })
//
//
// -- This will overwrite an existing command --
// Cypress.Commands.overwrite('visit', (originalFn, url, options) => { ... })

Cypress.Commands.add("AuthLogin", () => {
   cy.session("admin", () => {
      cy.log(`Logging in as ${Cypress.env("USER_EMAIL")}`);
      cy.request("POST", "/auth/login", {
         tenant: Cypress.env("TENANT"),
         email: Cypress.env("USER_EMAIL"),
         password: Cypress.env("USER_PASSWORD"),
      })
         .its("body")
         .as("currentUser");
   });
});

Cypress.Commands.add("DCSetCursor", (idDC, idRow) => {
   cy.window().then((win) => {
      let AB = win.AB;
      if (AB) {
         return AB.datacollectionByID(idDC).setCursor(idRow);
         // Question: Do you have any Idea how to make this wait for
         // the DC to be initialized before continuing?
         // maybe something like:
         // let DC = AB.datacollectionByID(idDC);
         // if (DC.dataStatus == DC.dataStatusFlag.initialized) {
         //    return DC.setCursor(idRow);
         // }
         // let settingCursor = new Promise((done) => {
         //    DC.once("initializedData", ()=>{
         //       DC.setCursor(idRow);
         //       done();
         //    })
         // });
         // return cy.wrap(settingCursor);
      }
      return null;
   });
});

/**
 * helper for scrolling in a grid
 * @function gridScroll
 * @param {string} id webix id of the grid
 * @param {int} h horizontal scroll in pixels
 * @param {int=0} v veritcal scroll in pixels
 */
Cypress.Commands.add("GridScroll", (id, h, v = 0) => {
   cy.window().then((win) => {
      return win.$$(id).scrollTo(h, v);
   });
});

Cypress.Commands.add("ModelCreate", (ID, data) => {
   cy.window().then((win) => {
      let AB = win.AB;
      if (AB) {
         return AB.objectByID(ID).model().create(data);
      }
      return null;
   });
});

Cypress.Commands.add("ModelDelete", (idModel, idRow) => {
   cy.window().then((win) => {
      let AB = win.AB;
      if (AB) {
         return AB.objectByID(idModel).model().delete(idRow);
      }
      return null;
   });
});

Cypress.Commands.add("ModelFind", (idModel, cond) => {
   cy.window().then((win) => {
      let AB = win.AB;
      if (AB) {
         return AB.objectByID(idModel).model().findAll(cond);
      }
      return null;
   });
});

Cypress.Commands.add("ModelUpdate", (idModel, idRow, data) => {
   cy.window().then((win) => {
      let AB = win.AB;
      if (AB) {
         return AB.objectByID(idModel).model().update(idRow, data);
      }
      return null;
   });
});

Cypress.Commands.add("ResetDB", () => {
   const stack = Cypress.env("STACK");

   // Clear the Physical DB
   cy.exec(`npm run test:reset ${stack}`, { failOnNonZeroExit: false });

   // Have the running services clear their definitions.
   cy.request("POST", "/test/reset", { tenant: Cypress.env("TENANT") });
});

Cypress.Commands.add("RunSQL", (folder, files, fail = true) => {
   const stack = Cypress.env("STACK");
   if (typeof files === "string") {
      files = [files];
   }

   const regEx = /^\S+/;
   cy.exec(`docker ps | grep ${stack}_db`).then(({ stdout }) => {
      if (!regEx.test(stdout)) {
         throw new Error(`couldn't find process matching '${stack}_db'`);
      }
      const containerId = stdout.match(regEx)[0];

      const user = Cypress.env("DB_USER");
      const password = Cypress.env("DB_PASSWORD");

      let catCmd = "cat ";
      files.forEach((file) => {
         const path = `./cypress/e2e/${folder}/test_setup/sql/${file} `;
         catCmd += path;
      });
      catCmd += `> ./cypress/e2e/${folder}/test_setup/sql/combineSql.sql`;
      cy.exec(catCmd);
      cy.exec(`docker exec ${containerId} mkdir -p /sql`);
      cy.exec(
         `docker cp ./cypress/e2e/${folder}/test_setup/sql/combineSql.sql ${containerId}:/sql/combineSql.sql`,
         {
            log: false,
         },
      );

      cy.exec(
         /* eslint-disable no-useless-escape*/
         `docker exec ${containerId} bash -c "mysql -u ${user} -p${password} \"appbuilder-admin\" < ./sql/combineSql.sql"`,
         { failOnNonZeroExit: fail },
      );
      cy.exec(`docker exec ${containerId} bash -c "rm ./sql/combineSql.sql"`, {
         log: false,
      });
      cy.exec(`rm ./cypress/e2e/${folder}/test_setup/sql/combineSql.sql`, {
         log: false,
      });
   });
});

Cypress.Commands.add("TestLog", (log) => {
   // Have the running services clear their definitions.
   cy.request("POST", "/testlog", { log });
});

Cypress.Commands.add("VersionCheck", () => {
   // have our Services report back their current versions.
   cy.request("GET", "/versioncheck", { tenant: Cypress.env("TENANT") });
});
