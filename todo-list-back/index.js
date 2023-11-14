const axios = require('axios');
const express = require('express');

const { initDb } = require('./config/db');

async function bootstrap() {
    const app = express();
    
    try {
        await initDb()
    } catch(e) {}
    
    app.use(express.json())

    const { TodosController } = require('./src/todos/todos.controller');

    TodosController.init(app)

    app.get('/get-zone', async (_req, res) => {
        try {
            const req = await axios.get('http://169.254.169.254/latest/meta-data/placement/availability-zone');
            res.send(req.data)
        } catch (e) {
            console.log(e)
            res.status(500).send('Something went wrong')
        }
    })

    app.get('/health', async (_req, res) => {
        res.send('Healthy')
    })

    const PORT = process.env.PORT
    app.listen(PORT, () => {
        console.log('successfuly listening on port: ', PORT)
    })
}
bootstrap()