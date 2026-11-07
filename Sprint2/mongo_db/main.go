package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func main() {
	ctx := context.Background()

	// Подключение к MongoDB
	client, err := mongo.Connect(ctx, options.Client().ApplyURI("mongodb://localhost:27017"))
	if err != nil {
		log.Fatal(err)
	}
	defer client.Disconnect(ctx)

	db := client.Database("service_center")

	// Три коллекции
	clients := db.Collection("clients")
	requests := db.Collection("requests")
	parts := db.Collection("parts")

	// Очищаем коллекции перед запуском
	clients.DeleteMany(ctx, bson.M{})
	requests.DeleteMany(ctx, bson.M{})
	parts.DeleteMany(ctx, bson.M{})

	// Создаём клиентов
	client1 := primitive.NewObjectID()
	client2 := primitive.NewObjectID()

	clients.InsertMany(ctx, []interface{}{
		bson.M{"_id": client1, "name": "Иван", "phone": "111111"},
		bson.M{"_id": client2, "name": "Пётр", "phone": "222222"},
	})

	// Создаём запчасти
	part1 := primitive.NewObjectID()
	part2 := primitive.NewObjectID()

	parts.InsertMany(ctx, []interface{}{
		bson.M{"_id": part1, "name": "Аккумулятор", "price": 3500},
		bson.M{"_id": part2, "name": "Экран", "price": 7000},
	})

	// Создаём заявки
	requests.InsertMany(ctx, []interface{}{
		bson.M{
			"client_id": client1,
			"equipment": bson.M{
				"name":  "Телефон",
				"model": "Samsung",
			},
			"description": "Быстро разряжается",
			"status":      "В работе",
			"parts": []bson.M{
				{"part_id": part1, "quantity": 1},
			},
			"date": time.Now(),
		},
		bson.M{
			"client_id": client1,
			"equipment": bson.M{
				"name":  "Телефон",
				"model": "Samsung",
			},
			"description": "Разбит экран",
			"status":      "Новая",
			"parts": []bson.M{
				{"part_id": part2, "quantity": 1},
			},
			"date": time.Now(),
		},
		bson.M{
			"client_id": client2,
			"equipment": bson.M{
				"name":  "Ноутбук",
				"model": "Lenovo",
			},
			"description": "Не заряжается",
			"status":      "В работе",
			"parts": []bson.M{
				{"part_id": part1, "quantity": 1},
				{"part_id": part2, "quantity": 1},
			},
			"date": time.Now(),
		},
	})

	fmt.Println("Данные добавлены!")

	// Находим заявки первого клиента
	fmt.Println("\nЗаявки Ивана:")

	cursor, err := requests.Find(ctx, bson.M{"client_id": client1})
	if err != nil {
		log.Fatal(err)
	}
	defer cursor.Close(ctx)

	for cursor.Next(ctx) {
		var request bson.M
		cursor.Decode(&request)
		fmt.Println(request["description"], "-", request["status"])
	}

	// Обновляем статус заявки
	_, err = requests.UpdateOne(
		ctx,
		bson.M{"description": "Разбит экран"},
		bson.M{"$set": bson.M{"status": "Готово"}},
	)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("\nСтатус заявки обновлён!")
}
