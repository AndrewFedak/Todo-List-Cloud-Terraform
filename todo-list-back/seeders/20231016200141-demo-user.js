'use strict';

const { v4: uuid } = require('uuid')

/** @type {import('sequelize-cli').Migration} */
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.bulkInsert('Todos', [{
      id: uuid(),
      title: 'John Doe',
      description: 'Something',
      isDone: false,
    }], {});
  },

  async down(queryInterface, Sequelize) {
     await queryInterface.bulkDelete('Todos', null, {});
  }
};
