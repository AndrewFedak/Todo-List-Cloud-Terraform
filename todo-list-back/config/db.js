const dotenv = require('dotenv');

module.exports.initDb = async () => {
    if(process.env.NODE_ENV !== 'production') {
        dotenv.config({ path: './.env' })
        dotenv.config({ path: './.aws.env' })
    }
    dotenv.config({ path: './.db.env' })
    
    const sequalize = require('../config/sequalize');
    await sequalize.authenticate()

    require('../models/todos');

    await sequalize.sync()
}