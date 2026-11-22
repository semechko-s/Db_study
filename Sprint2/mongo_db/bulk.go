package main

import (
	"context"
	"fmt"
	"io"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// bulkDemo models a parts catalog synchronization. It uses an isolated database
// so the example never modifies the team's service_center database.
func bulkDemo(client *mongo.Client, out io.Writer) (err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db := client.Database("service_center_bulk_demo_" + primitive.NewObjectID().Hex())
	defer func() {
		cleanupCtx, done := context.WithTimeout(context.Background(), 10*time.Second)
		defer done()
		if dropErr := db.Drop(cleanupCtx); err == nil && dropErr != nil {
			err = dropErr
		}
	}()
	if err := createBaselineIndexes(ctx, db); err != nil {
		return err
	}
	col := db.Collection("parts_catalog")
	now := time.Now().UTC()
	part := func(id int64, name, article, category string) bson.M {
		return bson.M{
			"pg_part_id": id, "category": category,
			"attributes":           bson.M{"stock_quantity": 5},
			"compatible_model_ids": bson.A{},
			"pg_snapshot":          bson.M{"name": name, "article": article, "synced_at": now},
		}
	}
	// Seed an existing part to make the update operation observable.
	if _, err := col.InsertOne(ctx, part(1001, "Экран", "SCR-1001", "display")); err != nil {
		return err
	}
	operations := []mongo.WriteModel{
		mongo.NewInsertOneModel().SetDocument(part(1002, "Аккумулятор", "BAT-1002", "battery")),
		mongo.NewInsertOneModel().SetDocument(part(1003, "Разъём", "USB-1003", "connector")),
		mongo.NewUpdateOneModel().SetFilter(bson.M{"pg_part_id": int64(1001)}).
			SetUpdate(bson.M{"$inc": bson.M{"attributes.stock_quantity": 7}}),
	}
	// Ordered execution is predictable for a teaching demo; error handling is
	// delegated to the teammate responsible for partial-failure scenarios.
	result, err := col.BulkWrite(ctx, operations, options.BulkWrite().SetOrdered(true))
	if err != nil {
		return fmt.Errorf("bulk write failed: %w", err)
	}
	count, err := col.CountDocuments(ctx, bson.M{})
	if err != nil {
		return err
	}
	var updated struct {
		Attributes struct {
			StockQuantity int `bson:"stock_quantity"`
		} `bson:"attributes"`
	}
	if err := col.FindOne(ctx, bson.M{"pg_part_id": int64(1001)}).Decode(&updated); err != nil {
		return err
	}
	if result.InsertedCount != 2 || result.ModifiedCount != 1 || count != 3 || updated.Attributes.StockQuantity != 12 {
		return fmt.Errorf("unexpected bulk results: inserted=%d modified=%d total=%d stock=%d", result.InsertedCount, result.ModifiedCount, count, updated.Attributes.StockQuantity)
	}
	_, err = fmt.Fprintf(out, "BulkWrite OK: inserted=%d matched=%d modified=%d total=%d updated_stock=%d\n", result.InsertedCount, result.MatchedCount, result.ModifiedCount, count, updated.Attributes.StockQuantity)
	return err
}
