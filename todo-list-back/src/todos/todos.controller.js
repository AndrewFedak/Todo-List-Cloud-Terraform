const { v4: uuid } = require('uuid')

const { Todo } = require("../../models/todos")

module.exports.TodosController = class {
    static init(app) {
        app.get('/todos', async (req, res) => {
            const todos = await Todo.findAll()
            res.send(todos)
        })
        app.get('/todos/:id', async (req, res) => {
            try {
                const todo = await Todo.findByPk(req.params.id)
                res.status(200).send(todo)
            } catch(e) {
                res.send(e.message)
            }
        })
        app.post('/todos', async (req, res) => {
            const { title, description } = req.body
            const todo = await Todo.create({ id: uuid(), title, description, isDone: false });
            res.send(todo)
        })
        app.patch('/todos/:id', async (req, res) => {
            await Todo.update(req.body, { where: { id: req.params.id } });
            const updatedTodo = await Todo.findByPk(req.params.id)
            res.status(200).send(updatedTodo)
        })
        app.delete('/todos/:id', async (req, res) => {
            await Todo.destroy({ where: { id: req.params.id } })
            res.status(200).send('deleted')
        })
    }
}