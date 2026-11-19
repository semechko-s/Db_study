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
)

const (
	benchmarkDocuments = 120000
	benchmarkRuns      = 5
)

type performanceQuery struct {
	collection string
	filter     bson.D
	order      bson.D
	index      bson.D
}

var performanceQueries = []performanceQuery{
	{
		collection: "request_events",
		filter:     bson.D{{Key: "author.pg_employee_id", Value: int64(42)}},
		order:      bson.D{{Key: "created_at", Value: -1}},
		index:      bson.D{{Key: "author.pg_employee_id", Value: 1}, {Key: "created_at", Value: -1}},
	},
	{
		collection: "diagnostic_reports",
		filter:     bson.D{{Key: "pg_diagnosis_id", Value: int64(42)}},
		order:      bson.D{{Key: "revision", Value: -1}},
		index:      bson.D{{Key: "pg_diagnosis_id", Value: 1}, {Key: "revision", Value: -1}},
	},
}

func createPerformanceIndexes(ctx context.Context, db *mongo.Database) error {
	for _, query := range performanceQueries {
		_, err := db.Collection(query.collection).Indexes().CreateOne(ctx, mongo.IndexModel{Keys: query.index})
		if err != nil {
			return fmt.Errorf("%s performance index: %w", query.collection, err)
		}
	}
	return nil
}

func seedBenchmark(ctx context.Context, db *mongo.Database) error {
	const batchSize = 1000
	start := time.Date(2025, time.January, 1, 0, 0, 0, 0, time.UTC)
	for offset := 0; offset < benchmarkDocuments; offset += batchSize {
		events := make([]interface{}, 0, batchSize)
		reports := make([]interface{}, 0, batchSize)
		for i := int64(offset); i < int64(offset+batchSize); i++ {
			events = append(events, bson.M{
				"pg_request_id": i%5000 + 1,
				"type":          "comment_added",
				"created_at":    start.Add(time.Duration(i) * time.Minute),
				"author":        bson.M{"pg_employee_id": i%1000 + 1},
				"payload":       bson.M{"text": "Diagnostic appointment confirmed"},
			})
			diagnosis := i % 10000
			reports = append(reports, bson.M{
				"pg_request_id":   diagnosis/2 + 1,
				"pg_diagnosis_id": diagnosis + 1,
				"revision":        2*(i/10000) + diagnosis%2 + 1,
				"kind":            "recheck",
				"checks":          bson.A{bson.M{"name": "power", "passed": true}},
				"found_faults":    bson.A{},
				"attachments":     bson.A{},
			})
		}
		if _, err := db.Collection("request_events").InsertMany(ctx, events); err != nil {
			return fmt.Errorf("seed request_events: %w", err)
		}
		if _, err := db.Collection("diagnostic_reports").InsertMany(ctx, reports); err != nil {
			return fmt.Errorf("seed diagnostic_reports: %w", err)
		}
	}
	return nil
}

type benchmarkMeasurement struct {
	MedianMillis int64             `json:"medianExecutionTimeMillis"`
	Explains     []json.RawMessage `json:"explains"`
}

func (q performanceQuery) measure(ctx context.Context, db *mongo.Database) (benchmarkMeasurement, error) {
	var result benchmarkMeasurement
	var millis []int64
	command := bson.D{
		{Key: "explain", Value: bson.D{
			{Key: "find", Value: q.collection},
			{Key: "filter", Value: q.filter},
			{Key: "sort", Value: q.order},
		}},
		{Key: "verbosity", Value: "executionStats"},
	}
	// Execute once before recording measurements to warm up the query's data.
	for run := 0; run <= benchmarkRuns; run++ {
		raw, err := db.RunCommand(ctx, command).Raw()
		if err != nil {
			return result, err
		}
		if run == 0 {
			continue
		}
		var stats struct {
			ExecutionStats struct {
				Millis int64 `bson:"executionTimeMillis"`
			} `bson:"executionStats"`
		}
		if err := bson.Unmarshal(raw, &stats); err != nil {
			return result, err
		}
		document, err := bson.MarshalExtJSON(raw, false, false)
		if err != nil {
			return result, err
		}
		millis = append(millis, stats.ExecutionStats.Millis)
		result.Explains = append(result.Explains, document)
	}
	sort.Slice(millis, func(i, j int) bool { return millis[i] < millis[j] })
	result.MedianMillis = millis[len(millis)/2]
	return result, nil
}

func benchmark(client *mongo.Client, output io.Writer) (err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	db := client.Database("service_center_benchmark_" + primitive.NewObjectID().Hex())
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if dropErr := db.Drop(cleanup); err == nil && dropErr != nil {
			err = fmt.Errorf("drop benchmark database: %w", dropErr)
		}
	}()
	if err := createBaselineIndexes(ctx, db); err != nil {
		return err
	}
	if err := seedBenchmark(ctx, db); err != nil {
		return err
	}

	type comparison struct {
		Collection string               `json:"collection"`
		Before     benchmarkMeasurement `json:"before"`
		After      benchmarkMeasurement `json:"after"`
	}
	results := make([]comparison, len(performanceQueries))
	for i, query := range performanceQueries {
		before, err := query.measure(ctx, db)
		if err != nil {
			return fmt.Errorf("%s before: %w", query.collection, err)
		}
		results[i] = comparison{Collection: query.collection, Before: before}
	}
	if err := createPerformanceIndexes(ctx, db); err != nil {
		return err
	}
	for i, query := range performanceQueries {
		after, err := query.measure(ctx, db)
		if err != nil {
			return fmt.Errorf("%s after: %w", query.collection, err)
		}
		results[i].After = after
	}

	encoder := json.NewEncoder(output)
	encoder.SetIndent("", "  ")
	return encoder.Encode(struct {
		DocumentsPerCollection int          `json:"documentsPerCollection"`
		Queries                []comparison `json:"queries"`
	}{benchmarkDocuments, results})
}
