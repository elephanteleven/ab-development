// Don't stop tests on uncaught errors
Cypress.on("uncaught:exception", () => false);

var isAppImported = false;
// {bool} have we already imported our Application Definitions?

describe("CARS:", () => {
   before(() => {
      cy.ResetDB();
   });

   beforeEach(() => {
      cy.AuthLogin();
      if (!isAppImported) {
         isAppImported = true;
         cy.request("POST", "/test/import", {
            file: "imports/test_import/app_test.json",
         });
      }
      cy.visit("/");
   });

   it("has CARS app in the Nav Menu", () => {
      NavigateCars(cy);

      // Should show CARS in the Menu Title
      cy.get("[data-cy=portal_work_menu_title]", { timeout: 90000 })
         .should("be.visible")
         .should("have.text", "CARS");

      // Should have 2 pages
      cy.get("[data-cy=portal_work_menu_pages]").then((elContainer) => {
         expect(elContainer[0].childElementCount).to.equal(2);
      });
   });
});

function NavigateCars(cy) {
   cy.get("[data-cy=portal_work_menu_sidebar]").should("be.visible").click();
   cy.get("[data-cy=45c62df9-ddd6-4744-84d6-50a2d549289d]")
      .should("be.visible")
      .click();
}
