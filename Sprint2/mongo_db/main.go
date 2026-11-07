package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const (
	databaseName = "service_center"
	requestsName = "service_requests"
)

var requestStatuses = []string{
	"Создана", "Принята", "На диагностике", "Ожидание",
	"В ремонте", "Готова", "Закрыта", "Отменена",
}

type Client struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	Name      string             `bson:"name"`
	Phone     string             `bson:"phone,omitempty"`
	Email     string             `bson:"email,omitempty"`
	CreatedAt time.Time          `bson:"created_at"`
}

type Part struct {
	ID    primitive.ObjectID `bson:"_id,omitempty"`
	Name  string             `bson:"name"`
	Price float64            `bson:"price"`
	Stock int32              `bson:"stock"`
}

type Equipment struct {
	Type         string `bson:"type"`
	Manufacturer string `bson:"manufacturer"`
	Model        string `bson:"model"`
	SerialNumber string `bson:"serial_number,omitempty"`
}

type RequestPart struct {
	PartID   primitive.ObjectID `bson:"part_id"`
	Quantity int32              `bson:"quantity"`
}

type RepairInfo struct {
	Status string  `bson:"status"`
	Cost   float64 `bson:"cost"`
	Result string  `bson:"result,omitempty"`
}

type ServiceRequest struct {
	ID             primitive.ObjectID `bson:"_id,omitempty"`
	ClientID       primitive.ObjectID `bson:"client_id"`
	Equipment      Equipment          `bson:"equipment"`
	Description    string             `bson:"description"`
	Status         string             `bson:"status"`
	WaitingReason  string             `bson:"waiting_reason,omitempty"`
	ClientApproved bool               `bson:"client_approved"`
	Parts          []RequestPart      `bson:"parts,omitempty"`
	Repair         *RepairInfo        `bson:"repair,omitempty"`
	CreatedAt      time.Time          `bson:"created_at"`
	UpdatedAt      time.Time          `bson:"updated_at"`
}

type Store struct {
	db       *mongo.Database
	clients  *mongo.Collection
	parts    *mongo.Collection
	requests *mongo.Collection
}

func main() {
	uri := os.Getenv("MONGODB_URI")
	if uri == "" {
		uri = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		log.Fatalf("подключение к MongoDB: %v", err)
	}
	defer func() {
		if err := client.Disconnect(context.Background()); err != nil {
			log.Printf("отключение от MongoDB: %v", err)
		}
	}()

	if err := client.Ping(ctx, nil); err != nil {
		log.Fatalf("MongoDB недоступна: %v", err)
	}

	store := NewStore(client.Database(databaseName))
	if err := store.EnsureSchema(ctx); err != nil {
		log.Fatalf("настройка коллекций и валидации: %v", err)
	}

	if len(os.Args) > 1 && os.Args[1] == "demo" {
		if err := runCRUDDemo(ctx, store); err != nil {
			log.Fatal(err)
		}
		return
	}

	fmt.Println("MongoDB подключена, коллекции и schema validation проверены.")
	fmt.Println("Для демонстрации CRUD выполните: go run . demo")
}

// NewStore связывает операции с тремя коллекциями документной модели.
func NewStore(db *mongo.Database) *Store {
	return &Store{
		db:       db,
		clients:  db.Collection("clients"),
		parts:    db.Collection("parts"),
		requests: db.Collection(requestsName),
	}
}

// EnsureSchema создаёт коллекции (если их ещё нет), включает JSON Schema validation
// и создаёт индексы. Существующие документы не удаляются.
func (s *Store) EnsureSchema(ctx context.Context) error {
	schemas := map[string]bson.M{
		"clients": {
			"bsonType": "object",
			"required": bson.A{"name", "created_at"},
			"properties": bson.M{
				"name":       bson.M{"bsonType": "string", "minLength": 1},
				"phone":      bson.M{"bsonType": "string"},
				"email":      bson.M{"bsonType": "string"},
				"created_at": bson.M{"bsonType": "date"},
			},
			"anyOf": bson.A{
				bson.M{"required": bson.A{"phone"}},
				bson.M{"required": bson.A{"email"}},
			},
		},
		"parts": {
			"bsonType": "object",
			"required": bson.A{"name", "price", "stock"},
			"properties": bson.M{
				"name":  bson.M{"bsonType": "string", "minLength": 1},
				"price": bson.M{"bsonType": bson.A{"int", "long", "double", "decimal"}, "minimum": 0},
				"stock": bson.M{"bsonType": "int", "minimum": 0},
			},
		},
		requestsName: {
			"bsonType": "object",
			"required": bson.A{"client_id", "equipment", "description", "status", "created_at", "updated_at"},
			"properties": bson.M{
				"client_id": bson.M{"bsonType": "objectId"},
				"equipment": bson.M{
					"bsonType": "object",
					"required": bson.A{"type", "manufacturer", "model"},
					"properties": bson.M{
						"type":          bson.M{"bsonType": "string", "minLength": 1},
						"manufacturer":  bson.M{"bsonType": "string", "minLength": 1},
						"model":         bson.M{"bsonType": "string", "minLength": 1},
						"serial_number": bson.M{"bsonType": "string"},
					},
				},
				"description":     bson.M{"bsonType": "string", "minLength": 1},
				"status":          bson.M{"bsonType": "string", "enum": stringsToBSON(requestStatuses)},
				"waiting_reason":  bson.M{"bsonType": "string"},
				"client_approved": bson.M{"bsonType": "bool"},
				"repair": bson.M{
					"bsonType": "object",
					"required": bson.A{"status", "cost"},
					"properties": bson.M{
						"status": bson.M{"bsonType": "string", "enum": bson.A{"Запланирован", "Выполняется", "Приостановлен", "Завершён", "Отменён"}},
						"cost":   bson.M{"bsonType": bson.A{"int", "long", "double", "decimal"}, "minimum": 0},
						"result": bson.M{"bsonType": "string"},
					},
				},
				"parts": bson.M{
					"bsonType": "array",
					"items": bson.M{
						"bsonType": "object",
						"required": bson.A{"part_id", "quantity"},
						"properties": bson.M{
							"part_id":  bson.M{"bsonType": "objectId"},
							"quantity": bson.M{"bsonType": "int", "minimum": 1},
						},
					},
				},
				"created_at": bson.M{"bsonType": "date"},
				"updated_at": bson.M{"bsonType": "date"},
			},
		},
	}

	for name, schema := range schemas {
		if err := s.ensureCollection(ctx, name, schema); err != nil {
			return err
		}
	}

	_, err := s.requests.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "client_id", Value: 1}, {Key: "created_at", Value: -1}},
	})
	if err != nil {
		return fmt.Errorf("индекс service_requests(client_id, created_at): %w", err)
	}
	_, err = s.parts.Indexes().CreateOne(ctx, mongo.IndexModel{
		Keys: bson.D{{Key: "name", Value: 1}},
	})
	if err != nil {
		return fmt.Errorf("индекс parts(name): %w", err)
	}
	return nil
}

func stringsToBSON(values []string) bson.A {
	result := make(bson.A, 0, len(values))
	for _, value := range values {
		result = append(result, value)
	}
	return result
}

func (s *Store) ensureCollection(ctx context.Context, name string, schema bson.M) error {
	names, err := s.db.ListCollectionNames(ctx, bson.M{"name": name})
	if err != nil {
		return fmt.Errorf("получение списка коллекций: %w", err)
	}
	validator := bson.M{"$jsonSchema": schema}
	if len(names) == 0 {
		err = s.db.CreateCollection(ctx, name, options.CreateCollection().SetValidator(validator).SetValidationLevel("strict").SetValidationAction("error"))
		if err != nil && !mongo.IsDuplicateKeyError(err) {
			return fmt.Errorf("создание коллекции %s: %w", name, err)
		}
		return nil
	}

	_, err = s.db.RunCommand(ctx, bson.D{
		{Key: "collMod", Value: name},
		{Key: "validator", Value: validator},
		{Key: "validationLevel", Value: "strict"},
		{Key: "validationAction", Value: "error"},
	}).Raw()
	if err != nil {
		return fmt.Errorf("обновление validator коллекции %s: %w", name, err)
	}
	return nil
}

// CRUD: clients.
func (s *Store) CreateClient(ctx context.Context, value Client) (primitive.ObjectID, error) {
	if value.Name == "" || (value.Phone == "" && value.Email == "") {
		return primitive.NilObjectID, errors.New("клиент должен иметь имя и телефон или email")
	}
	if value.CreatedAt.IsZero() {
		value.CreatedAt = time.Now().UTC()
	}
	result, err := s.clients.InsertOne(ctx, value)
	if err != nil {
		return primitive.NilObjectID, err
	}
	return result.InsertedID.(primitive.ObjectID), nil
}

func (s *Store) GetClient(ctx context.Context, id primitive.ObjectID) (*Client, error) {
	var value Client
	err := s.clients.FindOne(ctx, bson.M{"_id": id}).Decode(&value)
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func (s *Store) UpdateClient(ctx context.Context, id primitive.ObjectID, name, phone, email string) error {
	if name == "" || (phone == "" && email == "") {
		return errors.New("клиент должен иметь имя и телефон или email")
	}
	result, err := s.clients.UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$set": bson.M{
		"name": name, "phone": phone, "email": email,
	}})
	if err != nil {
		return err
	}
	if result.MatchedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

func (s *Store) DeleteClient(ctx context.Context, id primitive.ObjectID) error {
	used, err := s.requests.CountDocuments(ctx, bson.M{"client_id": id})
	if err != nil {
		return err
	}
	if used > 0 {
		return errors.New("нельзя удалить клиента: на него ссылаются заявки")
	}
	result, err := s.clients.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return err
	}
	if result.DeletedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

// CRUD: parts.
func (s *Store) CreatePart(ctx context.Context, value Part) (primitive.ObjectID, error) {
	if value.Name == "" || value.Price < 0 || value.Stock < 0 {
		return primitive.NilObjectID, errors.New("запчасть: имя обязательно, цена и остаток не могут быть отрицательными")
	}
	result, err := s.parts.InsertOne(ctx, value)
	if err != nil {
		return primitive.NilObjectID, err
	}
	return result.InsertedID.(primitive.ObjectID), nil
}

func (s *Store) GetPart(ctx context.Context, id primitive.ObjectID) (*Part, error) {
	var value Part
	err := s.parts.FindOne(ctx, bson.M{"_id": id}).Decode(&value)
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func (s *Store) UpdatePart(ctx context.Context, id primitive.ObjectID, price float64, stock int32) error {
	if price < 0 || stock < 0 {
		return errors.New("цена и остаток не могут быть отрицательными")
	}
	result, err := s.parts.UpdateOne(ctx, bson.M{"_id": id}, bson.M{"$set": bson.M{"price": price, "stock": stock}})
	if err != nil {
		return err
	}
	if result.MatchedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

func (s *Store) DeletePart(ctx context.Context, id primitive.ObjectID) error {
	used, err := s.requests.CountDocuments(ctx, bson.M{"parts.part_id": id})
	if err != nil {
		return err
	}
	if used > 0 {
		return errors.New("нельзя удалить запчасть: она используется в заявках")
	}
	result, err := s.parts.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return err
	}
	if result.DeletedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

// validateRequest реализует междокументные бизнес-правила, которые JSON Schema
// не может проверить самостоятельно.
func (s *Store) validateRequest(ctx context.Context, value ServiceRequest) error {
	if value.ClientID.IsZero() {
		return errors.New("client_id обязателен")
	}
	if err := s.clients.FindOne(ctx, bson.M{"_id": value.ClientID}).Err(); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return errors.New("указанный клиент не существует")
		}
		return err
	}
	if value.Description == "" || value.Equipment.Type == "" ||
		value.Equipment.Manufacturer == "" || value.Equipment.Model == "" {
		return errors.New("описание и основные поля оборудования обязательны")
	}
	if !contains(requestStatuses, value.Status) {
		return fmt.Errorf("недопустимый статус заявки: %s", value.Status)
	}
	if (value.Status == "В ремонте" || value.Status == "Готова" || value.Status == "Закрыта") && !value.ClientApproved {
		return errors.New("для этого статуса требуется согласие клиента")
	}
	if value.Status == "Ожидание" && value.WaitingReason == "" {
		return errors.New("для статуса «Ожидание» требуется waiting_reason")
	}
	if value.Status != "Ожидание" && value.WaitingReason != "" {
		return errors.New("waiting_reason можно указывать только для статуса «Ожидание»")
	}
	seen := make(map[primitive.ObjectID]bool)
	if value.Repair != nil {
		validRepairStatuses := []string{"Запланирован", "Выполняется", "Приостановлен", "Завершён", "Отменён"}
		if !contains(validRepairStatuses, value.Repair.Status) || value.Repair.Cost < 0 {
			return errors.New("ремонт должен иметь допустимый статус и неотрицательную стоимость")
		}
		if value.Repair.Status == "Завершён" && value.Repair.Result == "" {
			return errors.New("для завершённого ремонта требуется результат")
		}
	}
	for _, item := range value.Parts {
		if item.PartID.IsZero() || item.Quantity <= 0 {
			return errors.New("каждая запчасть должна иметь part_id и положительное quantity")
		}
		if seen[item.PartID] {
			return errors.New("одна запчасть не должна повторяться в массиве заявки")
		}
		seen[item.PartID] = true
		if err := s.parts.FindOne(ctx, bson.M{"_id": item.PartID}).Err(); err != nil {
			if errors.Is(err, mongo.ErrNoDocuments) {
				return fmt.Errorf("запчасть %s не существует", item.PartID.Hex())
			}
			return err
		}
	}
	return nil
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

// CRUD: service_requests.
func (s *Store) CreateRequest(ctx context.Context, value ServiceRequest) (primitive.ObjectID, error) {
	if err := s.validateRequest(ctx, value); err != nil {
		return primitive.NilObjectID, err
	}
	now := time.Now().UTC()
	if value.CreatedAt.IsZero() {
		value.CreatedAt = now
	}
	value.UpdatedAt = now
	result, err := s.requests.InsertOne(ctx, value)
	if err != nil {
		return primitive.NilObjectID, err
	}
	return result.InsertedID.(primitive.ObjectID), nil
}

func (s *Store) GetRequest(ctx context.Context, id primitive.ObjectID) (*ServiceRequest, error) {
	var value ServiceRequest
	err := s.requests.FindOne(ctx, bson.M{"_id": id}).Decode(&value)
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func (s *Store) UpdateRequest(ctx context.Context, id primitive.ObjectID, value ServiceRequest) error {
	if err := s.validateRequest(ctx, value); err != nil {
		return err
	}
	value.UpdatedAt = time.Now().UTC()
	parts := value.Parts
	if parts == nil {
		parts = []RequestPart{}
	}
	setFields := bson.M{
		"client_id": value.ClientID, "equipment": value.Equipment,
		"description": value.Description, "status": value.Status,
		"waiting_reason": value.WaitingReason, "client_approved": value.ClientApproved,
		"parts": parts, "updated_at": value.UpdatedAt,
	}
	update := bson.M{"$set": setFields}
	if value.Repair != nil {
		setFields["repair"] = value.Repair
	} else {
		update["$unset"] = bson.M{"repair": ""}
	}
	result, err := s.requests.UpdateOne(ctx, bson.M{"_id": id}, update)
	if err != nil {
		return err
	}
	if result.MatchedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

func (s *Store) DeleteRequest(ctx context.Context, id primitive.ObjectID) error {
	result, err := s.requests.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		return err
	}
	if result.DeletedCount == 0 {
		return mongo.ErrNoDocuments
	}
	return nil
}

// runCRUDDemo создаёт только собственные демонстрационные документы.
// В отличие от старой версии программы, коллекции не очищаются.
func runCRUDDemo(ctx context.Context, s *Store) error {
	suffix := time.Now().UTC().Format("20060102T150405.000000000")
	clientID, err := s.CreateClient(ctx, Client{
		Name: "Демо-клиент " + suffix, Phone: "+70000000000",
	})
	if err != nil {
		return fmt.Errorf("создание клиента: %w", err)
	}
	clientRecord, err := s.GetClient(ctx, clientID)
	if err != nil {
		_ = s.DeleteClient(ctx, clientID)
		return fmt.Errorf("чтение клиента: %w", err)
	}
	if err := s.UpdateClient(ctx, clientID, clientRecord.Name+" (обновлён)", clientRecord.Phone, clientRecord.Email); err != nil {
		_ = s.DeleteClient(ctx, clientID)
		return fmt.Errorf("обновление клиента: %w", err)
	}
	fmt.Println("CLIENT CRUD: создание, чтение и обновление выполнены")

	partID, err := s.CreatePart(ctx, Part{
		Name: "Демо-запчасть " + suffix, Price: 1200, Stock: 3,
	})
	if err != nil {
		_ = s.DeleteClient(ctx, clientID)
		return fmt.Errorf("создание запчасти: %w", err)
	}
	var requestID primitive.ObjectID
	defer func() {
		if !requestID.IsZero() {
			_ = s.DeleteRequest(ctx, requestID)
		}
		_ = s.DeletePart(ctx, partID)
		_ = s.DeleteClient(ctx, clientID)
	}()

	partRecord, err := s.GetPart(ctx, partID)
	if err != nil {
		return fmt.Errorf("чтение запчасти: %w", err)
	}
	if err := s.UpdatePart(ctx, partID, partRecord.Price+100, partRecord.Stock); err != nil {
		return fmt.Errorf("обновление запчасти: %w", err)
	}
	fmt.Println("PART CRUD: создание, чтение и обновление выполнены")

	requestID, err = s.CreateRequest(ctx, ServiceRequest{
		ClientID:    clientID,
		Equipment:   Equipment{Type: "Ноутбук", Manufacturer: "Lenovo", Model: "ThinkPad"},
		Description: "Демонстрационная заявка", Status: "Создана",
		Parts: []RequestPart{{PartID: partID, Quantity: 1}},
	})
	if err != nil {
		return fmt.Errorf("создание заявки: %w", err)
	}

	created, err := s.GetRequest(ctx, requestID)
	if err != nil {
		return fmt.Errorf("чтение заявки: %w", err)
	}
	fmt.Printf("CREATE + READ: заявка %s, статус %s\n", created.ID.Hex(), created.Status)

	created.Status = "Принята"
	if err := s.UpdateRequest(ctx, requestID, *created); err != nil {
		return fmt.Errorf("обновление заявки: %w", err)
	}
	updated, err := s.GetRequest(ctx, requestID)
	if err != nil {
		return err
	}
	fmt.Printf("UPDATE: новый статус %s\n", updated.Status)

	if err := s.DeleteRequest(ctx, requestID); err != nil {
		return fmt.Errorf("удаление заявки: %w", err)
	}
	fmt.Println("DELETE: демонстрационная заявка удалена")
	if err := s.DeletePart(ctx, partID); err != nil {
		return fmt.Errorf("удаление демонстрационной запчасти: %w", err)
	}
	if err := s.DeleteClient(ctx, clientID); err != nil {
		return fmt.Errorf("удаление демонстрационного клиента: %w", err)
	}
	fmt.Println("DELETE: демонстрационные клиент и запчасть удалены")
	return nil
}
