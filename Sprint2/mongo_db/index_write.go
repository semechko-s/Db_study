package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const writeDocuments = 20000
const writeRuns = 5

type indexWriteMeasurement struct {
	WithExtraIndex bool    `json:"withExtraIndex"`
	Run            int     `json:"run"`
	Millis         float64 `json:"insertMillis"`
	DocsPerSecond  float64 `json:"documentsPerSecond"`
	Count          int64   `json:"count" bson:"count"`
	Size           int64   `json:"size" bson:"size"`
	StorageSize    int64   `json:"storageSize" bson:"storageSize"`
	TotalIndexSize int64   `json:"totalIndexSize" bson:"totalIndexSize"`
	NIndexes       int64   `json:"nindexes" bson:"nindexes"`
}

// Each run has a fresh database. Documents and write settings remain identical.
func measureIndexWrite(ctx context.Context, client *mongo.Client, docs []interface{}, extra bool, run int) (result indexWriteMeasurement, err error) {
	db := client.Database("service_center_index_write_" + primitive.NewObjectID().Hex())
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if dropErr := db.Drop(cleanup); err == nil && dropErr != nil {
			err = fmt.Errorf("cleanup: %w", dropErr)
		}
	}()
	if err = createBaselineIndexes(ctx, db); err != nil {
		return result, err
	}
	collection := db.Collection("request_events")
	if extra {
		_, err = collection.Indexes().CreateOne(ctx, mongo.IndexModel{
			Keys: bson.D{{Key: "author.pg_employee_id", Value: 1}, {Key: "created_at", Value: -1}},
		})
		if err != nil {
			return result, err
		}
	}
	start := time.Now()
	for offset := 0; offset < len(docs); offset += 1000 {
		end := offset + 1000
		if end > len(docs) {
			end = len(docs)
		}
		if _, err = collection.InsertMany(ctx, docs[offset:end], options.InsertMany().SetOrdered(true)); err != nil {
			return result, err
		}
	}
	elapsed := time.Since(start)
	count, err := collection.CountDocuments(ctx, bson.D{})
	if err != nil {
		return result, err
	}
	if count != int64(len(docs)) {
		return result, fmt.Errorf("expected %d documents, got %d", len(docs), count)
	}
	// Flush data outside the timed interval so disk statistics include the inserts.
	// Run this benchmark on a separate local test server; fsync affects the server.
	if err = client.Database("admin").RunCommand(ctx, bson.D{{Key: "fsync", Value: 1}}).Err(); err != nil {
		return result, fmt.Errorf("flush before storage measurement: %w", err)
	}
	if err = db.RunCommand(ctx, bson.D{{Key: "collStats", Value: "request_events"}, {Key: "scale", Value: 1}}).Decode(&result); err != nil {
		return result, err
	}
	result.WithExtraIndex = extra
	result.Run = run
	result.Millis = elapsed.Seconds() * 1000
	result.DocsPerSecond = float64(count) / elapsed.Seconds()
	expectedIndexes := int64(3) // _id, request/time, sparse history ID.
	if extra {
		expectedIndexes++
	}
	if result.Count != count || result.NIndexes != expectedIndexes {
		return result, fmt.Errorf("unexpected collection statistics: %+v", result)
	}
	return result, nil
}

func indexWriteBenchmark(client *mongo.Client, output io.Writer) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	docs := make([]interface{}, 0, writeDocuments)
	for i := 0; i < writeDocuments; i++ {
		docs = append(docs, bson.D{
			{Key: "_id", Value: int64(i + 1)},
			{Key: "pg_request_id", Value: int64(i%5000 + 1)},
			{Key: "type", Value: "comment_added"},
			{Key: "created_at", Value: start.Add(time.Duration(i) * time.Minute)},
			{Key: "author", Value: bson.D{{Key: "pg_employee_id", Value: int64(i%1000 + 1)}}},
			{Key: "payload", Value: bson.D{{Key: "text", Value: "Diagnostic appointment confirmed"}}},
		})
	}
	var measurements []indexWriteMeasurement
	// Run zero warms up each variant and is excluded from the results.
	for run := 0; run <= writeRuns; run++ {
		variants := []bool{false, true}
		if run%2 == 0 {
			variants = []bool{true, false}
		}
		for _, extra := range variants {
			result, err := measureIndexWrite(ctx, client, docs, extra, run)
			if err != nil {
				return fmt.Errorf("run %d, extra index=%t: %w", run, extra, err)
			}
			if run != 0 {
				measurements = append(measurements, result)
			}
		}
	}
	medians := map[string]float64{}
	for _, extra := range []bool{false, true} {
		var times []float64
		for _, result := range measurements {
			if result.WithExtraIndex == extra {
				times = append(times, result.Millis)
			}
		}
		sort.Float64s(times)
		name := "baseline"
		if extra {
			name = "extraIndex"
		}
		medians[name] = times[len(times)/2]
	}
	encoder := json.NewEncoder(output)
	encoder.SetIndent("", "  ")
	return encoder.Encode(struct {
		Documents int                     `json:"documentsPerRun"`
		Runs      []indexWriteMeasurement `json:"runs"`
		Medians   map[string]float64      `json:"medianInsertMillis"`
	}{writeDocuments, measurements, medians})
}
