// Don't stop tests on uncaught errors
Cypress.on("uncaught:exception", () => false);
const SITE_USER = "228e3d91-5e42-49ec-b37c-59323ae433a1";
const ROLE = "c33692f3-26b7-4af3-a02e-139fb519296d";
const SWITCHEROO = "320ef94a-73b5-476e-9db4-c08130c64bb8";
const SYSTEM_ADMIN_ROLE = "dd6c2d34-0982-48b7-bc44-2456474edbea";
const DEFAULT_ROLE_PROCESS = "3ce49e36-4c1b-4058-b734-126865fdd8d9";

describe("portal_work:", () => {
   before(() => {
      cy.ResetDB();
      cy.AuthLogin();
      // Give admin the switcheroo role
      cy.request("put", `/app_builder/model/${ROLE}/${SWITCHEROO}`, {
         users: [{ username: "admin" }],
      });
      // Delete the process since it will overwrite the test user roles in
      // we assign in the next request
      cy.request("delete", `/definition/${DEFAULT_ROLE_PROCESS}`);
      // Create a user we can switch to
      cy.request({
         method: "post",
         url: `/app_builder/model/${SITE_USER}`,
         body: {
            username: "test",
            email: "test@email.com",
            isActive: true,
            SITE_ROLE: [{ uuid: SYSTEM_ADMIN_ROLE }],
            languageCode: "en",
         },
         failOnStatusCode: false,
      });
   });

   beforeEach(() => {
      cy.AuthLogin();
      cy.request("delete", "/auth/switcheroo");
      cy.visit("/");
   });

   it("has Site Admin in the Nav Menu", () => {
      NavigateSiteAdmin(cy);

      // Should show Site Admin in the Menu Title
      cy.get("[data-cy=portal_work_menu_title]")
         .should("be.visible")
         .should("have.text", "Site Administration");

      // Should have 1 page
      cy.get("[data-cy=portal_work_menu_pages]").then((elContainer) => {
         expect(elContainer[0].childElementCount).to.equal(1);
      });

      // Should see the Inbox
      cy.get("[data-cy=inbox_icon]").should("be.visible");

      // Should see the User icon
      cy.get("[data-cy=user_icon]").should("be.visible");

      // Should have the AB factory available in the Window
      cy.window().should("have.property", "AB");
   });

   it("can use switcheroo", () => {
      // Switch
      cy.get('[data-cy="user_icon"]').as("userMenu");
      cy.get("@userMenu").should("be.visible").click();
      cy.get('[data-cy="user_switcheroo"]').should("be.visible").click();
      cy.get('[data-cy="switcheroo_user_list"]').should("be.visible").click();
      cy.get('[data-cy="switcheroo_option_test"]').should("be.visible").click();
      waitReloadCommand(cy, () => {
         cy.get('[data-cy="switcheroo_switch_button"]')
            .should("be.visible")
            .click();
      });
      // Expect the switcheroo banner to be displayed
      cy.get(".portal_work_switcheroo_user_switched")
         .should("be.visible")
         .and("contain", "test");
      checkUsernameInProfile(cy, "test");
      // Swith back
      waitReloadCommand(cy, () => {
         cy.get('[data-cy="switcheroo_clear_button"]')
            .should("be.visible")
            .click();
      });
      cy.get(".portal_work_switcheroo_user_switched").should("not.exist");
      checkUsernameInProfile(cy, "admin");
   });
});

function NavigateSiteAdmin(cy) {
   cy.get("[data-cy=portal_work_menu_sidebar]").should("be.visible").click();
   cy.get("[data-cy=227bcbb3-437f-4bb5-a5a1-ec3198696206]")
      .should("be.visible")
      .click();
}

/**
 * test that the given username displays in the user profile
 * @param {Cypress} cy
 * @param {string} username
 */
function checkUsernameInProfile(cy, username) {
   cy.get('[data-cy="user_icon"]').should("be.visible").click();
   cy.get('[data-cy="user_profile"]').should("be.visible").click();
   cy.get('[data-cy="user_profile_username"]')
      .should("be.visible")
      .and("contain", username);
   cy.get('[data-cy="user-profile-close"]').should("be.visible").click();
}

/**
 * If we are trigger a site reload (from the app) we need to wait for the reload
 * to happen. Adapted from: https://github.com/cypress-io/cypress/issues/1805#issuecomment-525482440
 * @param {Cypress} cy
 * @param {Function} command function that runs the command to reload the site.
 */
function waitReloadCommand(cy, command) {
   cy.window().then((w) => (w.needsReload = true));
   command(cy);
   cy.window().should("not.have.prop", "needsReload");
}

