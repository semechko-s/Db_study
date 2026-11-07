package main

import (
	"context"
	"os"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func TestRequestBusinessRules(t *testing.T) {
	uri := os.Getenv("MONGODB_URI")
	if uri == "" {
		uri = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Disconnect(context.Background())

	if err := client.Ping(ctx, nil); err != nil {
		t.Fatalf("MongoDB недоступна: %v", err)
	}

	db := client.Database("service_center_go_tests")
	defer db.Drop(context.Background())

	store := NewStore(db)
	if err := store.EnsureSchema(ctx); err != nil {
		t.Fatalf("настройка тестовой схемы: %v", err)
	}

	clientID, err := store.CreateClient(ctx, Client{
		Name:  "Тестовый клиент",
		Phone: "+70000000000",
	})
	if err != nil {
		t.Fatalf("создание тестового клиента: %v", err)
	}

	validRequest := ServiceRequest{
		ClientID: clientID,
		Equipment: Equipment{
			Type:         "Ноутбук",
			Manufacturer: "Test",
			Model:        "Model 1",
		},
		Description: "Тестовая заявка",
		Status:      "Создана",
	}

	t.Run("несуществующий клиент", func(t *testing.T) {
		request := validRequest
		request.ClientID = primitive.NewObjectID()

		if _, err := store.CreateRequest(ctx, request); err == nil {
			t.Fatal("ожидалась ошибка для несуществующего клиента")
		}
	})

	t.Run("ремонт без согласия", func(t *testing.T) {
		request := validRequest
		request.Status = "В ремонте"
		request.ClientApproved = false

		if _, err := store.CreateRequest(ctx, request); err == nil {
			t.Fatal("ожидалась ошибка при отсутствии согласия клиента")
		}
	})

	t.Run("ожидание без причины", func(t *testing.T) {
		request := validRequest
		request.Status = "Ожидание"
		request.WaitingReason = ""

		if _, err := store.CreateRequest(ctx, request); err == nil {
			t.Fatal("ожидалась ошибка при отсутствии причины ожидания")
		}
	})

	t.Run("корректная заявка", func(t *testing.T) {
		request := validRequest

		if _, err := store.CreateRequest(ctx, request); err != nil {
			t.Fatalf("корректная заявка отклонена: %v", err)
		}
	})

	t.Run("обновление без согласия", func(t *testing.T) {
		request := validRequest

		id, err := store.CreateRequest(ctx, request)
		if err != nil {
			t.Fatalf("создание заявки: %v", err)
		}

		request.Status = "В ремонте"
		request.ClientApproved = false

		if err := store.UpdateRequest(ctx, id, request); err == nil {
			t.Fatal("ожидалась ошибка при обновлении без согласия клиента")
		}
	})
}
