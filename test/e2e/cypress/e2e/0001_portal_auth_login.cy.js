// Don't stop tests on uncaught errors
Cypress.on("uncaught:exception", () => false);

const USER_EMAIL = Cypress.env("USER_EMAIL");
const USER_PASSWORD = Cypress.env("USER_PASSWORD");

describe("Login Page", () => {
   before(() => {
      // make sure we have a clean slate before continuing.
      cy.ResetDB();
   });

   beforeEach(() => {
      cy.visit("/");
   });

   // 1) Successful Login
   it("loads the login page", () => {
      Login(USER_EMAIL, USER_PASSWORD);

      // warning should NOT exist
      cy.get("[data-cy=portal_auth_login_form_errormsg]").should("not.exist");

      // but the menu bar should
      cy.get("[data-cy=portal_work_menu_sidebar]").should("be.visible");
   });

   // 2) Successful Logout
   it("Logging out, returns you to the Login Form:", () => {
      Login(USER_EMAIL, USER_PASSWORD);
      cy.get("[data-cy=user_icon]").should("be.visible").click();
      cy.get("[data-cy=user_logout]").should("be.visible").click();
   });

   // 3) Login Error Messages
   it("Displays Error Message when invalid Username / Password", () => {
      Login(`a${USER_EMAIL}`, USER_PASSWORD);

      // now the warning should exist
      cy.get("[data-cy=portal_auth_login_form_errormsg]").should("exist");
   });
});

describe("Reset Password", () => {
   before(() => {
      cy.ResetDB();
   });
   it("Can change a password", () => {
      cy.visit("/");
      cy.get('[data-cy="portal_auth_login_forgot"]')
         .should("be.visible")
         .click();
      cy.get('[data-cy="portal_reset_request_email"]')
         .should("be.visible")
         .type(USER_EMAIL);
      cy.get('[data-cy="portal_reset_request_send"]')
         .should("be.visible")
         .click();
      // The user would now recieve an email with a link, including a site token
      // we'll retrieve the generated token and create the link;
      // Login to get token - don't use cy.AuthLogin since we won't reuse this
      // session
      cy.request("POST", "/auth/login", {
         tenant: Cypress.env("TENANT"),
         email: USER_EMAIL,
         password: USER_PASSWORD,
      })
         .its("body")
         .as("currentUser");
      // reload to get a new ABFactory in the window (authenticated)
      cy.visit("/");
      cy.ModelFind("08826ac7-4b33-4745-a3d7-f7831ca4ff59", {}).then(
         ({ data }) => {
            const { token } = data[0];
            // now that we have the token logout an simulate the link from email;
            logOut();
            cy.visit(`/auth/password/reset?a=${token}`);
            const password = "newpassword";
            cy.get('[data-cy="portal_reset_password_new"]')

               .should("be.visible")
               .type(password);
            cy.get('[data-cy="portal_reset_password_confirm"]')
               .should("be.visible")
               .type(password);
            cy.get('[data-cy="portal_reset_password_submit"]')
               .should("be.visible")
               .click();
            logOut();
            // Check the new passwor works
            Login(USER_EMAIL, password);
            cy.get("[data-cy=portal_work_menu_sidebar]").should("be.visible");
         },
      );
   });
});

describe.skip("Loading", () => {
   before(() => {
      const url = Cypress.config("baseUrl");
      const parts = url.split("//");
      Cypress.config("baseUrl", `${parts[0]}//fake.${parts[1]}`);
   });
   it("shows error when tenant not found", () => {
      cy.visit("/", { failOnStatusCode: false });
      cy.contains("couldn't find the tenant 'fake'");
   });
});

function Login(email, passowrd) {
   cy.getCookies().should((cookie) => {
      console.log(cookie);
   });
   cy.get("input[data-cy=portal_auth_login_form_email]").type(email);
   cy.get("input[data-cy=portal_auth_login_form_password]").type(passowrd);
   cy.get("[data-cy=portal_auth_login_form_submit]").click();
}

function logOut() {
   cy.get('[data-cy="user_icon"]').should("be.visible").click();
   cy.get('[data-cy="user_logout"]').should("be.visible").click();
}
