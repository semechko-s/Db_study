package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	uri := os.Getenv("MONGODB_URI")
	if uri == "" {
		uri = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		return err
	}
	defer client.Disconnect(context.Background())

	if len(os.Args) == 2 && (os.Args[1] == "demo" || os.Args[1] == "model-demo") {
		db := client.Database("service_center_demo_" + primitive.NewObjectID().Hex())
		defer func() {
			if err := db.Drop(context.Background()); err != nil {
				log.Printf("Не удалось удалить временную базу %s: %v", db.Name(), err)
			}
		}()
		if err := createCollections(ctx, db); err != nil {
			return err
		}
		return demo(ctx, db)
	}
	if len(os.Args) > 1 && (len(os.Args) != 2 || os.Args[1] != "model") {
		return fmt.Errorf("использование: go run . [demo]")
	}
	return createCollections(ctx, client.Database("service_center"))
}

func createCollections(ctx context.Context, db *mongo.Database) error {
	// При создании индекса MongoDB также создаёт коллекцию, если её ещё нет.
	indexes := map[string]bson.D{
		"equipment_models":   {{Key: "model_key", Value: 1}},
		"parts_catalog":      {{Key: "compatible_model_ids", Value: 1}},
		"diagnostic_reports": {{Key: "pg_request_id", Value: 1}, {Key: "revision", Value: 1}},
		"request_events":     {{Key: "pg_request_id", Value: 1}, {Key: "created_at", Value: -1}},
	}
	for name, keys := range indexes {
		if _, err := db.Collection(name).Indexes().CreateOne(ctx, mongo.IndexModel{Keys: keys}); err != nil {
			return fmt.Errorf("коллекция %s: %w", name, err)
		}
	}
	return nil
}

func demo(ctx context.Context, db *mongo.Database) error {
	modelA, modelB := primitive.NewObjectID(), primitive.NewObjectID()
	requestID := int64(101)

	models := db.Collection("equipment_models")
	_, err := models.InsertMany(ctx, []interface{}{
		bson.M{"_id": modelA, "type": "Ноутбук", "manufacturer": "Demo", "model": "A", "model_key": "demo|a", "specs": bson.M{"screen_inches": 14}},
		bson.M{"_id": modelB, "type": "Ноутбук", "manufacturer": "Demo", "model": "B", "model_key": "demo|b", "specs": bson.M{"screen_inches": 15}},
	})
	if err != nil {
		return err
	}

	parts := db.Collection("parts_catalog")
	_, err = parts.InsertMany(ctx, []interface{}{
		bson.M{"pg_part_id": int64(201), "category": "Аккумулятор", "attributes": bson.M{"capacity_wh": 48}, "compatible_model_ids": bson.A{modelA, modelB}},
		bson.M{"pg_part_id": int64(202), "category": "Адаптер", "attributes": bson.M{"power_w": 65}, "compatible_model_ids": bson.A{modelA, modelB}},
	})
	if err != nil {
		return err
	}

	reports := db.Collection("diagnostic_reports")
	_, err = reports.InsertMany(ctx, []interface{}{
		bson.M{"pg_request_id": requestID, "revision": 1, "kind": "initial", "checks": bson.A{bson.M{"name": "Зарядка", "passed": false}}},
		bson.M{"pg_request_id": requestID, "revision": 2, "kind": "recheck", "checks": bson.A{bson.M{"name": "Зарядка", "passed": true}}},
	})
	if err != nil {
		return err
	}

	fmt.Printf("1:N — протоколы заявки %d со встроенными проверками:\n", requestID)
	cursor, err := reports.Find(ctx, bson.M{"pg_request_id": requestID})
	if err != nil {
		return err
	}
	var revisions []bson.M
	if err := cursor.All(ctx, &revisions); err != nil {
		return err
	}
	for _, report := range revisions {
		fmt.Printf("Ревизия %v: %v\n", report["revision"], report["checks"])
	}

	fmt.Println("M:N — запчасти для каждой модели:")
	for _, model := range []primitive.ObjectID{modelA, modelB} {
		cursor, err := parts.Find(ctx, bson.M{"compatible_model_ids": model})
		if err != nil {
			return err
		}
		var compatibleParts []bson.M
		if err := cursor.All(ctx, &compatibleParts); err != nil {
			return err
		}
		fmt.Printf("Модель %s:", model.Hex())
		for _, part := range compatibleParts {
			fmt.Printf(" %v", part["category"])
		}
		fmt.Println()
	}
	return nil
}
