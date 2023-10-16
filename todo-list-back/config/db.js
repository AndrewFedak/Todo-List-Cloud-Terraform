const dotenv = require('dotenv');

module.exports.initDb = async () => {
    dotenv.config({ path: './.env' })
    if(process.env.NODE_ENV !== 'production') {
        dotenv.config({ path: './.db.env' })
        dotenv.config({ path: './.aws.env' })
    }
    
    const sequalize = require('../config/sequalize');
    await sequalize.authenticate()

    require('../models/todos');

    await sequalize.sync()
}