/**
 * Common.js
 * Provides a set of common capability for our test suites.
 *
 * AuthLogin()
 * The result of this fn() will be to set a logged in user's
 * Cookie in our cy test runner object.
 *
 * ResetDB()
 * Clears the database back to it's initial starting state, and
 * makes sure our running services reset their Definitions.
 */
module.exports = {
   AuthLogin: function (cy) {
      cy.log("Refactored: Use cy.AuthLogin()");
      cy.AuthLogin();
   },

   ResetDB: function (cy) {
      cy.log("Refactored: Use cy.ResetDB()");
      cy.ResetDB();
   },

   RunSQL: function (cy, folder, files) {
      cy.log("Refactored: use cy.RunSQL(folder, files)");
      cy.RunSQL(folder, files, false);
   },
};
