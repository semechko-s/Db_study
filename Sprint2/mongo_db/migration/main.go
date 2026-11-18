// Independent v1/v2 migration. Only reports and their backup collection are written.
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/bsontype"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/writeconcern"
)

const reports = "diagnostic_reports"
const backups = "diagnostic_reports_v1_v2_backup"

type snapshot struct {
	ID     interface{} `bson:"_id"`
	Before bson.Raw    `bson:"before"`
	After  bson.Raw    `bson:"after"`
}

func safeDB(name string) bool {
	return strings.HasPrefix(name, "migration_test_") && len(name) > len("migration_test_")
}

// Preserve BSON types, field order and unknown fields, including nested extensions.
// Duplicate BSON keys have ambiguous lookup semantics; never migrate them.
func uniqueKeys(value bson.RawValue) error {
	if value.Type == bson.TypeEmbeddedDocument {
		elements, err := value.Document().Elements()
		if err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, e := range elements {
			if seen[e.Key()] {
				return fmt.Errorf("duplicate BSON key %q", e.Key())
			}
			seen[e.Key()] = true
			if err = uniqueKeys(e.Value()); err != nil {
				return err
			}
		}
	} else if value.Type == bson.TypeArray {
		values, err := value.Array().Values()
		if err != nil {
			return err
		}
		for _, v := range values {
			if err = uniqueKeys(v); err != nil {
				return err
			}
		}
	}
	return nil
}
func version(d bson.Raw) (int, error) {
	if err := d.Validate(); err != nil {
		return 0, err
	}
	if err := uniqueKeys(bson.RawValue{Type: bson.TypeEmbeddedDocument, Value: d}); err != nil {
		return 0, err
	}
	for _, k := range []string{"pg_request_id", "pg_diagnosis_id", "revision"} {
		n, ok := d.Lookup(k).Int64OK()
		if !ok || n < 1 {
			return 0, fmt.Errorf("%s must be positive BSON long", k)
		}
	}
	kind, ok := d.Lookup("kind").StringValueOK()
	if !ok || strings.TrimSpace(kind) == "" {
		return 0, fmt.Errorf("invalid kind")
	}
	if d.Lookup("revision").Int64() != 1 && kind != "recheck" {
		return 0, fmt.Errorf("revision requires recheck")
	}
	for _, k := range []string{"found_faults", "attachments"} {
		if _, ok := d.Lookup(k).ArrayOK(); !ok {
			return 0, fmt.Errorf("%s must be array", k)
		}
	}
	checks, ok := d.Lookup("checks").ArrayOK()
	if !ok {
		return 0, fmt.Errorf("checks must be array")
	}
	v, f := d.Lookup("schema_version"), d.Lookup("report_format")
	ver := 0
	if v.Type == 0 && f.Type == 0 {
		ver = 1
	} else if (v.Type == bson.TypeInt32 && v.Int32() == 1 || v.Type == bson.TypeInt64 && v.Int64() == 1) && f.Type == 0 {
		ver = 1
	} else if (v.Type == bson.TypeInt32 && v.Int32() == 2 || v.Type == bson.TypeInt64 && v.Int64() == 2) && f.Type == bson.TypeString && f.StringValue() == "diagnostic.v2" {
		ver = 2
	} else {
		return 0, fmt.Errorf("unknown schema version or report_format")
	}
	values, err := checks.Values()
	if err != nil {
		return 0, err
	}
	for _, value := range values {
		c, ok := value.DocumentOK()
		if !ok {
			return 0, fmt.Errorf("invalid check")
		}
		name, ok := c.Lookup("name").StringValueOK()
		if !ok || strings.TrimSpace(name) == "" {
			return 0, fmt.Errorf("invalid check name")
		}
		if ver == 1 {
			if _, ok := c.Lookup("passed").BooleanOK(); !ok || c.Lookup("status").Type != 0 {
				return 0, fmt.Errorf("v1 check requires passed bool without status")
			}
		} else {
			status, ok := c.Lookup("status").StringValueOK()
			if !ok || (status != "pass" && status != "fail" && status != "skipped") || c.Lookup("passed").Type != 0 {
				return 0, fmt.Errorf("v2 check requires status pass/fail/skipped without passed")
			}
		}
	}
	return ver, nil
}
func upgrade(raw bson.Raw) (bson.Raw, error) {
	if v, err := version(raw); err != nil || v != 1 {
		return nil, fmt.Errorf("upgrade requires valid v1: %v", err)
	}
	var d bson.D
	if err := bson.Unmarshal(raw, &d); err != nil {
		return nil, err
	}
	out := bson.D{}
	for _, e := range d {
		if e.Key == "schema_version" {
			continue
		}
		if e.Key != "checks" {
			out = append(out, e)
			continue
		}
		arr, ok := e.Value.(bson.A)
		if !ok {
			return nil, fmt.Errorf("checks decoding error")
		}
		converted := bson.A{}
		for _, entry := range arr {
			check, ok := entry.(bson.D)
			if !ok {
				return nil, fmt.Errorf("check decoding error")
			}
			newCheck := bson.D{}
			for _, field := range check {
				if field.Key == "passed" {
					passed, ok := field.Value.(bool)
					if !ok {
						return nil, fmt.Errorf("invalid passed")
					}
					status := "fail"
					if passed {
						status = "pass"
					}
					newCheck = append(newCheck, bson.E{Key: "status", Value: status})
				} else {
					newCheck = append(newCheck, field)
				}
			}
			converted = append(converted, newCheck)
		}
		out = append(out, bson.E{Key: "checks", Value: converted})
	}
	out = append(out, bson.E{Key: "schema_version", Value: int32(2)}, bson.E{Key: "report_format", Value: "diagnostic.v2"})
	return bson.Marshal(out)
}
func scan(ctx context.Context, c *mongo.Collection) ([]bson.Raw, error) {
	cur, err := c.Find(ctx, bson.D{})
	if err != nil {
		return nil, err
	}
	defer cur.Close(ctx)
	var out []bson.Raw
	for cur.Next(ctx) {
		out = append(out, append(bson.Raw(nil), cur.Current...))
	}
	return out, cur.Err()
}
func identifier(raw bson.Raw) interface{} { var d bson.M; _ = bson.Unmarshal(raw, &d); return d["_id"] }

// MongoDB equality equates numerically equal int/long/double values. Also
// compare the recursive BSON type tree so a concurrent type change is not lost.
func mongoType(t bsontype.Type) string {
	names := map[bsontype.Type]string{bson.TypeDouble: "double", bson.TypeString: "string", bson.TypeEmbeddedDocument: "object", bson.TypeArray: "array", bson.TypeBinary: "binData", bson.TypeUndefined: "undefined", bson.TypeObjectID: "objectId", bson.TypeBoolean: "bool", bson.TypeDateTime: "date", bson.TypeNull: "null", bson.TypeRegex: "regex", bson.TypeDBPointer: "dbPointer", bson.TypeJavaScript: "javascript", bson.TypeSymbol: "symbol", bson.TypeCodeWithScope: "javascriptWithScope", bson.TypeInt32: "int", bson.TypeTimestamp: "timestamp", bson.TypeInt64: "long", bson.TypeDecimal128: "decimal", bson.TypeMinKey: "minKey", bson.TypeMaxKey: "maxKey"}
	return names[t]
}
func typeGuards(value bson.RawValue, expr interface{}) bson.A {
	guards := bson.A{bson.M{"$eq": bson.A{bson.M{"$type": expr}, mongoType(value.Type)}}}
	if value.Type == bson.TypeEmbeddedDocument {
		elements, _ := value.Document().Elements()
		for _, e := range elements {
			child := bson.M{"$getField": bson.M{"field": bson.M{"$literal": e.Key()}, "input": expr}}
			guards = append(guards, typeGuards(e.Value(), child)...)
		}
	}
	if value.Type == bson.TypeArray {
		values, _ := value.Array().Values()
		for i, v := range values {
			guards = append(guards, typeGuards(v, bson.M{"$arrayElemAt": bson.A{expr, i}})...)
		}
	}
	return guards
}
func replace(ctx context.Context, c *mongo.Collection, from, to bson.Raw) error {
	guards := typeGuards(bson.RawValue{Type: bson.TypeEmbeddedDocument, Value: from}, "$$ROOT")
	guards = append(guards, bson.M{"$eq": bson.A{"$$ROOT", bson.M{"$literal": from}}})
	targetVersion, err := version(to)
	if err != nil {
		return err
	}
	// v2 cannot satisfy the unchanged legacy validator. v1 rollback must satisfy it.
	opts := options.Replace().SetBypassDocumentValidation(targetVersion == 2).SetCollation(&options.Collation{Locale: "simple"})
	r, err := c.ReplaceOne(ctx, bson.M{"_id": identifier(from), "$expr": bson.M{"$and": guards}}, to, opts)
	if err != nil {
		return err
	}
	if r.MatchedCount != 1 {
		return fmt.Errorf("concurrent modification: retry after inspection")
	}
	return nil
}

func run(ctx context.Context, db *mongo.Database, cmd string) error {
	docs, err := scan(ctx, db.Collection(reports))
	if err != nil {
		return err
	}
	counts := [3]int{}
	for _, d := range docs {
		v, e := version(d)
		if e != nil {
			return fmt.Errorf("incompatible document %v: %w", identifier(d), e)
		}
		counts[v]++
	}
	fmt.Printf("v1=%d v2=%d\n", counts[1], counts[2])
	if cmd == "status" {
		return nil
	}
	// Preflight all backup records before any report mutation.
	var plans []snapshot
	if cmd == "up" {
		for _, d := range docs {
			v, _ := version(d)
			if v != 1 {
				continue
			}
			after, e := upgrade(d)
			if e != nil {
				return e
			}
			p := snapshot{identifier(d), d, after}
			var old snapshot
			e = db.Collection(backups).FindOne(ctx, bson.M{"_id": p.ID}).Decode(&old)
			if e == nil {
				if !bytes.Equal(old.Before, p.Before) || !bytes.Equal(old.After, p.After) {
					return fmt.Errorf("backup conflict for %v", p.ID)
				}
			} else if e != mongo.ErrNoDocuments {
				return e
			}
			plans = append(plans, p)
		}
		for _, p := range plans {
			_, e := db.Collection(backups).InsertOne(ctx, p)
			if e != nil {
				if !mongo.IsDuplicateKeyError(e) {
					return fmt.Errorf("backup: %w", e)
				}
				var old snapshot
				if e = db.Collection(backups).FindOne(ctx, bson.M{"_id": p.ID}).Decode(&old); e != nil {
					return e
				}
				if !bytes.Equal(old.Before, p.Before) || !bytes.Equal(old.After, p.After) {
					return fmt.Errorf("backup changed")
				}
			}
			if e = replace(ctx, db.Collection(reports), p.Before, p.After); e != nil {
				return e
			}
		}
	} else if cmd == "down" {
		raw, err := scan(ctx, db.Collection(backups))
		if err != nil {
			return err
		}
		for _, r := range raw {
			var p snapshot
			if err = bson.Unmarshal(r, &p); err != nil {
				return err
			}
			v, e := version(p.Before)
			if e != nil || v != 1 {
				return fmt.Errorf("invalid backup")
			}
			expected, e := upgrade(p.Before)
			if e != nil || !bytes.Equal(expected, p.After) {
				return fmt.Errorf("invalid backup postimage")
			}
			var current bson.Raw
			if e = db.Collection(reports).FindOne(ctx, bson.M{"_id": p.ID}).Decode(&current); e != nil {
				return fmt.Errorf("missing report or read error: %w", e)
			}
			if bytes.Equal(current, p.Before) {
				continue
			}
			if !bytes.Equal(current, p.After) {
				return fmt.Errorf("rollback refused for %v: document changed since migration; backup retained", p.ID)
			}
			plans = append(plans, p)
		}
		for _, p := range plans {
			if err = replace(ctx, db.Collection(reports), p.After, p.Before); err != nil {
				return err
			}
		}
	} else {
		return fmt.Errorf("unknown command")
	}
	fmt.Printf("%s: changed=%d; backups retained\n", cmd, len(plans))
	return nil
}
func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: migration status|up|down --db migration_test_NAME [--uri URI]")
	}
	cmd := os.Args[1]
	if cmd != "status" && cmd != "up" && cmd != "down" {
		log.Fatal("unknown command")
	}
	flags := flag.NewFlagSet("migration", flag.ExitOnError)
	name := flags.String("db", "", "explicit temporary database")
	uri := flags.String("uri", os.Getenv("MONGODB_URI"), "MongoDB URI")
	_ = flags.Parse(os.Args[2:])
	if flags.NArg() != 0 {
		log.Fatal("unexpected arguments")
	}
	if !safeDB(*name) {
		log.Fatal("only migration_test_* databases are allowed; service_center is forbidden")
	}
	if *uri == "" {
		*uri = "mongodb://localhost:27017"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	c, err := mongo.Connect(ctx, options.Client().ApplyURI(*uri).SetWriteConcern(writeconcern.Majority()))
	if err != nil {
		log.Fatal(err)
	}
	defer c.Disconnect(context.Background())
	if err = c.Ping(ctx, nil); err != nil {
		log.Fatal(err)
	}
	db := c.Database(*name)
	err = run(ctx, db, cmd)
	if err != nil {
		log.Fatal(err)
	}
}
