const { Sequelize } = require("sequelize");

const sequalize = new Sequelize({
    database: 'postgres',
    username: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    host: process.env.DB_HOST,
    port: 5432,
    dialect: 'postgres',
    dialectOptions: {
        ssl: {
            rejectUnauthorized: false, // This option is required for SSL connections to Amazon RDS.
        },
    },
});

module.exports = sequalize