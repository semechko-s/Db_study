package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// bulkDemo demonstrates unordered synchronization of independent parts.
// The duplicate-key operation is intentional: it proves that MongoDB continues
// processing the remaining operations and that the caller handles partial errors.
// The demo uses an isolated database and never modifies service_center.
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

	// Existing document is the target of UpdateOne and the duplicate-key test.
	if _, err := col.InsertOne(ctx, part(1001, "Экран", "SCR-1001", "display")); err != nil {
		return err
	}

	operations := []mongo.WriteModel{
		mongo.NewInsertOneModel().SetDocument(part(1002, "Аккумулятор", "BAT-1002", "battery")),
		// This insert must fail because pg_part_id=1001 already exists.
		mongo.NewInsertOneModel().SetDocument(part(1001, "Дубликат", "DUP-1001", "display")),
		mongo.NewUpdateOneModel().SetFilter(bson.M{"pg_part_id": int64(1001)}).
			SetUpdate(bson.M{"$inc": bson.M{"attributes.stock_quantity": 7}}),
		mongo.NewInsertOneModel().SetDocument(part(1003, "Разъём", "USB-1003", "connector")),
	}

	// Unordered is appropriate because catalog synchronization operations are
	// independent: one bad part must not prevent valid parts from being synced.
	result, bulkErr := col.BulkWrite(ctx, operations, options.BulkWrite().SetOrdered(false))
	if bulkErr == nil {
		return fmt.Errorf("expected duplicate-key error was not returned")
	}

	var writeErr mongo.BulkWriteException

	if !errors.As(bulkErr, &writeErr) {
		var writeErrPtr *mongo.BulkWriteException
		if !errors.As(bulkErr, &writeErrPtr) || writeErrPtr == nil {
			return fmt.Errorf("bulk write failed for a reason other than a partial write error: %w", bulkErr)
		}
		writeErr = *writeErrPtr
	}

	if writeErr.WriteConcernError != nil {
		return fmt.Errorf("bulk write concern error: %w", writeErr.WriteConcernError)
	}
	if len(writeErr.WriteErrors) != 1 {
		return fmt.Errorf("expected one failed operation, got %d: %w", len(writeErr.WriteErrors), bulkErr)
	}
	failed := writeErr.WriteErrors[0]
	if failed.Index != 1 || failed.Code != 11000 {
		return fmt.Errorf("unexpected bulk write error at operation %d (code %d): %s", failed.Index, failed.Code, failed.Message)
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
		return fmt.Errorf("unexpected partial bulk results: inserted=%d modified=%d total=%d stock=%d", result.InsertedCount, result.ModifiedCount, count, updated.Attributes.StockQuantity)
	}

	_, err = fmt.Fprintf(out,
		"Unordered BulkWrite handled partial failure: inserted=%d matched=%d modified=%d total=%d updated_stock=%d\n"+
			"Expected error: operation=%d code=%d message=%q\n",
		result.InsertedCount, result.MatchedCount, result.ModifiedCount, count,
		updated.Attributes.StockQuantity, failed.Index, failed.Code, failed.Message)
	return err
}
