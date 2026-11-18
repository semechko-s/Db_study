package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var collections = []string{"equipment_models", "parts_catalog", "diagnostic_reports", "request_events"}

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	uri := os.Getenv("MONGODB_URI")
	if uri == "" {
		uri = "mongodb://localhost:27017"
	}
	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		log.Fatal(err)
	}
	defer client.Disconnect(context.Background())
	if err = client.Ping(ctx, nil); err != nil {
		log.Fatal(err)
	}
	if len(os.Args) == 2 && os.Args[1] == "demo" {
		db := client.Database("service_center_demo_" + primitive.NewObjectID().Hex())
		defer db.Drop(context.Background())
		if err = demo(ctx, db); err != nil {
			log.Fatal(err)
		}
		return
	}
	if len(os.Args) > 1 {
		log.Fatal("usage: go run . [demo]")
	}
	if err = createIndexes(ctx, client.Database("service_center")); err != nil {
		log.Fatal(err)
	}
	fmt.Println("MongoDB готова")
}

func createIndexes(ctx context.Context, db *mongo.Database) error {
	indexes := map[string][]mongo.IndexModel{
		"equipment_models": {{Keys: bson.D{{Key: "model_key", Value: 1}}, Options: options.Index().SetUnique(true)}},
		"parts_catalog": {
			{Keys: bson.D{{Key: "pg_part_id", Value: 1}}, Options: options.Index().SetUnique(true)},
			{Keys: bson.D{{Key: "compatible_model_ids", Value: 1}}},
		},
		"diagnostic_reports": {{Keys: bson.D{{Key: "pg_request_id", Value: 1}, {Key: "revision", Value: 1}}, Options: options.Index().SetUnique(true)}},
		"request_events": {
			{Keys: bson.D{{Key: "pg_request_id", Value: 1}, {Key: "created_at", Value: -1}}},
			{Keys: bson.D{{Key: "pg_status_history_id", Value: 1}}, Options: options.Index().SetUnique(true).SetSparse(true)},
		},
	}
	for name, models := range indexes {
		if _, err := db.Collection(name).Indexes().CreateMany(ctx, models); err != nil {
			return fmt.Errorf("%s indexes: %w", name, err)
		}
	}
	return ensureValidators(ctx, db)
}

func ensureValidators(ctx context.Context, db *mongo.Database) error {
	str := bson.M{"bsonType": "string", "minLength": 1}
	long := bson.M{"bsonType": "long", "minimum": int64(1)}
	obj, arr := bson.M{"bsonType": "object"}, bson.M{"bsonType": "array"}
	validators := map[string]bson.M{
		"equipment_models": {"$jsonSchema": bson.M{
			"bsonType": "object", "required": bson.A{"type", "manufacturer", "model", "model_key", "specs"},
			"properties": bson.M{"type": str, "manufacturer": str, "model": str, "model_key": str, "specs": obj, "common_faults": arr, "typical_cost_range": obj},
		}},
		"parts_catalog": {"$jsonSchema": bson.M{
			"bsonType": "object", "required": bson.A{"pg_part_id", "category", "attributes", "compatible_model_ids"},
			"properties": bson.M{
				"pg_part_id": long, "category": str, "attributes": obj,
				"compatible_model_ids": bson.M{"bsonType": "array", "items": bson.M{"bsonType": "objectId"}},
				"install_notes":        str,
				"pg_snapshot":          bson.M{"bsonType": "object", "required": bson.A{"name", "article", "synced_at"}, "properties": bson.M{"name": str, "article": str, "synced_at": bson.M{"bsonType": "date"}}},
			},
		}},
		"diagnostic_reports": {"$jsonSchema": bson.M{
			"bsonType": "object", "required": bson.A{"pg_request_id", "pg_diagnosis_id", "revision", "kind", "checks", "found_faults", "attachments"},
			"properties": bson.M{
				"pg_request_id": long, "pg_diagnosis_id": long, "revision": long, "kind": str,
				"checks":       bson.M{"bsonType": "array", "items": bson.M{"bsonType": "object", "required": bson.A{"name", "passed"}, "properties": bson.M{"name": str, "passed": bson.M{"bsonType": "bool"}}}},
				"found_faults": arr, "attachments": arr,
			},
		}},
		"request_events": {"$and": bson.A{
			bson.M{"$jsonSchema": bson.M{"bsonType": "object", "required": bson.A{"pg_request_id", "type", "created_at", "author", "payload"}, "properties": bson.M{
				"pg_request_id": long, "type": str, "created_at": bson.M{"bsonType": "date"},
				"author":  bson.M{"bsonType": "object", "required": bson.A{"pg_employee_id"}, "properties": bson.M{"pg_employee_id": long}},
				"payload": obj, "pg_status_history_id": long,
			}}},
			bson.M{"$or": bson.A{
				bson.M{"type": bson.M{"$ne": "status_changed"}},
				bson.M{"pg_status_history_id": bson.M{"$type": "long", "$gt": int64(0)}, "payload.old_status": bson.M{"$type": "string", "$ne": ""}, "payload.new_status": bson.M{"$type": "string", "$ne": ""}},
			}},
		}},
	}

	existing, err := db.ListCollectionNames(ctx, bson.M{})
	if err != nil {
		return err
	}
	found := make(map[string]bool, len(existing))
	for _, name := range existing {
		found[name] = true
	}
	for name, validator := range validators {
		if found[name] {
			err = db.RunCommand(ctx, bson.D{{Key: "collMod", Value: name}, {Key: "validator", Value: validator}, {Key: "validationLevel", Value: "strict"}, {Key: "validationAction", Value: "error"}}).Err()
		} else {
			opts := options.CreateCollection().SetValidator(validator).SetValidationLevel("strict").SetValidationAction("error")
			err = db.CreateCollection(ctx, name, opts)
		}
		if err != nil {
			return fmt.Errorf("%s validator: %w", name, err)
		}
	}
	return nil
}

func contains(collection string) bool {
	for _, name := range collections {
		if collection == name {
			return true
		}
	}
	return false
}

func str(v interface{}) bool             { s, ok := v.(string); return ok && strings.TrimSpace(s) != "" }
func id(v interface{}) bool              { n, ok := v.(int64); return ok && n > 0 }
func doc(v interface{}) (bson.M, bool)   { d, ok := v.(bson.M); return d, ok }
func array(v interface{}) (bson.A, bool) { a, ok := v.(bson.A); return a, ok }

// validate checks application-level rules and references between MongoDB collections.
// Existence of PostgreSQL IDs must be checked by the application integration layer.
func validate(ctx context.Context, db *mongo.Database, c string, d bson.M) error {
	if !contains(c) || d == nil {
		return fmt.Errorf("unknown collection or empty document")
	}
	switch c {
	case "equipment_models":
		if !str(d["manufacturer"]) || !str(d["model"]) || d["model_key"] != strings.ToLower(d["manufacturer"].(string))+"|"+strings.ToLower(d["model"].(string)) {
			return fmt.Errorf("invalid model_key or model fields")
		}
	case "parts_catalog":
		if !id(d["pg_part_id"]) {
			return fmt.Errorf("pg_part_id must be positive int64")
		}
		ids, ok := array(d["compatible_model_ids"])
		if !ok {
			return fmt.Errorf("compatible_model_ids must be an array")
		}
		seen := map[primitive.ObjectID]bool{}
		for _, value := range ids {
			modelID, ok := value.(primitive.ObjectID)
			if !ok || seen[modelID] {
				return fmt.Errorf("invalid or duplicate model ID")
			}
			seen[modelID] = true
			if err := db.Collection("equipment_models").FindOne(ctx, bson.M{"_id": modelID}).Err(); err != nil {
				return fmt.Errorf("compatible model not found: %w", err)
			}
		}
	case "diagnostic_reports":
		if !id(d["pg_request_id"]) || !id(d["pg_diagnosis_id"]) || !id(d["revision"]) {
			return fmt.Errorf("report IDs and revision must be positive int64")
		}
		if d["revision"] != int64(1) && d["kind"] != "recheck" {
			return fmt.Errorf("revision after the initial report must have kind recheck")
		}
	case "request_events":
		if d["type"] == "status_changed" {
			p, ok := doc(d["payload"])
			if !id(d["pg_status_history_id"]) || !ok || !str(p["old_status"]) || !str(p["new_status"]) {
				return fmt.Errorf("status_changed requires history ID and old/new status")
			}
		}
	}
	return nil
}

func Create(ctx context.Context, db *mongo.Database, c string, d bson.M) (interface{}, error) {
	if c == "request_events" && d != nil && d["type"] == "status_changed" {
		return nil, fmt.Errorf("use UpsertStatusChanged")
	}
	if err := validate(ctx, db, c, d); err != nil {
		return nil, err
	}
	result, err := db.Collection(c).InsertOne(ctx, d)
	if err != nil {
		return nil, err
	}
	return result.InsertedID, nil
}

func Read(ctx context.Context, db *mongo.Database, c string, id interface{}) (bson.M, error) {
	if !contains(c) {
		return nil, fmt.Errorf("unknown collection: %s", c)
	}
	var result bson.M
	err := db.Collection(c).FindOne(ctx, bson.M{"_id": id}).Decode(&result)
	return result, err
}

func Update(ctx context.Context, db *mongo.Database, c string, id interface{}, changes bson.M) error {
	if !contains(c) || c == "request_events" || len(changes) == 0 {
		return fmt.Errorf("unknown collection, append-only collection or empty update")
	}
	for key := range changes {
		if key == "_id" || strings.HasPrefix(key, "$") || strings.Contains(key, ".") {
			return fmt.Errorf("only top-level fields can be updated: %s", key)
		}
	}
	current, err := Read(ctx, db, c, id)
	if err != nil {
		return err
	}
	for key, value := range changes {
		current[key] = value
	}
	if err = validate(ctx, db, c, current); err != nil {
		return err
	}
	result, err := db.Collection(c).UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$set": changes})
	if err == nil && result.MatchedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return err
}

func Delete(ctx context.Context, db *mongo.Database, c string, id interface{}) error {
	if !contains(c) || c == "request_events" {
		return fmt.Errorf("unknown collection or request_events is append-only")
	}
	if c == "equipment_models" {
		n, err := db.Collection("parts_catalog").CountDocuments(ctx, bson.M{"compatible_model_ids": id})
		if err != nil {
			return err
		}
		if n > 0 {
			return fmt.Errorf("model is referenced by parts_catalog")
		}
	}
	result, err := db.Collection(c).DeleteOne(ctx, bson.M{"_id": id})
	if err == nil && result.DeletedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return err
}

func UpsertStatusChanged(ctx context.Context, db *mongo.Database, d bson.M) (interface{}, error) {
	if d == nil || d["type"] != "status_changed" {
		return nil, fmt.Errorf("expected status_changed")
	}
	if _, exists := d["_id"]; exists {
		return nil, fmt.Errorf("_id is generated by MongoDB")
	}
	if err := validate(ctx, db, "request_events", d); err != nil {
		return nil, err
	}
	filter := bson.M{"pg_status_history_id": d["pg_status_history_id"]}
	if _, err := db.Collection("request_events").UpdateOne(ctx, filter, bson.M{"$set": d}, options.Update().SetUpsert(true)); err != nil {
		return nil, err
	}
	var saved bson.M
	err := db.Collection("request_events").FindOne(ctx, filter).Decode(&saved)
	return saved["_id"], err
}

func demo(ctx context.Context, db *mongo.Database) error {
	if err := createIndexes(ctx, db); err != nil {
		return err
	}
	modelID, err := Create(ctx, db, "equipment_models", bson.M{"type": "laptop", "manufacturer": "Demo", "model": "A", "model_key": "demo|a", "specs": bson.M{"ram": 8}, "common_faults": bson.A{}})
	if err != nil {
		return err
	}
	if _, err = db.Collection("equipment_models").InsertOne(ctx, bson.M{"manufacturer": "invalid"}); err == nil {
		return fmt.Errorf("MongoDB validator accepted invalid model")
	}
	partID, err := Create(ctx, db, "parts_catalog", bson.M{"pg_part_id": int64(1), "category": "battery", "attributes": bson.M{}, "compatible_model_ids": bson.A{modelID}, "pg_snapshot": bson.M{"name": "Battery", "article": "BAT-1", "synced_at": time.Now()}})
	if err != nil {
		return err
	}
	if err = Delete(ctx, db, "equipment_models", modelID); err == nil {
		return fmt.Errorf("referenced model was deleted")
	}
	if err = Update(ctx, db, "parts_catalog", partID, bson.M{"install_notes": "demo"}); err != nil {
		return err
	}
	if err = Update(ctx, db, "parts_catalog", partID, bson.M{"attributes.ram": 16}); err == nil {
		return fmt.Errorf("dotted update key was accepted")
	}
	report := bson.M{"pg_request_id": int64(1), "pg_diagnosis_id": int64(1), "revision": int64(1), "kind": "initial", "checks": bson.A{bson.M{"name": "power", "passed": true}}, "found_faults": bson.A{}, "attachments": bson.A{}}
	reportID, err := Create(ctx, db, "diagnostic_reports", report)
	if err != nil {
		return err
	}
	if _, err = Read(ctx, db, "diagnostic_reports", reportID); err != nil {
		return err
	}
	if err = Update(ctx, db, "diagnostic_reports", reportID, bson.M{"checks": bson.A{bson.M{"name": "power", "passed": false}}}); err != nil {
		return err
	}
	recheck := bson.M{"pg_request_id": int64(1), "pg_diagnosis_id": int64(1), "revision": int64(2), "kind": "recheck", "checks": bson.A{}, "found_faults": bson.A{}, "attachments": bson.A{}}
	recheckID, err := Create(ctx, db, "diagnostic_reports", recheck)
	if err != nil {
		return err
	}
	if err = Delete(ctx, db, "diagnostic_reports", reportID); err != nil {
		return err
	}
	if err = Delete(ctx, db, "diagnostic_reports", recheckID); err != nil {
		return err
	}
	event := bson.M{"pg_request_id": int64(1), "type": "status_changed", "created_at": time.Now(), "author": bson.M{"pg_employee_id": int64(1)}, "payload": bson.M{"old_status": "new", "new_status": "done"}, "pg_status_history_id": int64(1)}
	eventID, err := UpsertStatusChanged(ctx, db, event)
	if err != nil {
		return err
	}
	event["payload"] = bson.M{"old_status": "new", "new_status": "closed"}
	updatedID, err := UpsertStatusChanged(ctx, db, event)
	if err != nil || updatedID != eventID {
		return fmt.Errorf("status upsert failed: %v", err)
	}
	saved, err := Read(ctx, db, "request_events", eventID)
	if err != nil {
		return err
	}
	payload, _ := doc(saved["payload"])
	if payload["new_status"] != "closed" || Update(ctx, db, "request_events", eventID, bson.M{}) == nil || Delete(ctx, db, "request_events", eventID) == nil {
		return fmt.Errorf("request_events restrictions or upsert failed")
	}
	ordinaryID, err := Create(ctx, db, "request_events", bson.M{"pg_request_id": int64(1), "type": "comment_added", "created_at": time.Now(), "author": bson.M{"pg_employee_id": int64(1)}, "payload": bson.M{"text": "demo"}})
	if err != nil {
		return err
	}
	if _, err = Read(ctx, db, "request_events", ordinaryID); err != nil {
		return err
	}
	fmt.Println("Smoke test passed")
	return nil
}
