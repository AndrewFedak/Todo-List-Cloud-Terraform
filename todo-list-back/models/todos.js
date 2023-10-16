const { DataTypes } = require('sequelize')

const sequalize = require('../config/sequalize')

const Todo = sequalize.define(
    'Todos',
    {
        id: {
            type: DataTypes.UUID,
            defaultValue: DataTypes.UUIDV4,
            primaryKey: true
        },
        title: {
            type: DataTypes.STRING,
            allowNull: false
        },
        description: {
            type: DataTypes.STRING,
            allowNull: true
        },
        isDone: {
            type: DataTypes.BOOLEAN,
            defaultValue: false
        }
    }
)

module.exports.Todo = Todo
