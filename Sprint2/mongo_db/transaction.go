package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

func transactionDemo(ctx context.Context, client *mongo.Client) error {
	db := client.Database("service_center_tx_" + primitive.NewObjectID().Hex())
	defer db.Drop(context.Background())

	if err := createBaselineIndexes(ctx, db); err != nil {
		return fmt.Errorf("transaction setup: %w", err)
	}

	reports := db.Collection("diagnostic_reports")
	events := db.Collection("request_events")

	baseID := time.Now().UnixNano()

	// Сценарий 1. Обе операции должны завершиться успешно.
	successID := baseID
	if err := runTransaction(ctx, client, func(sc mongo.SessionContext) (interface{}, error) {
		if _, err := reports.InsertOne(sc, makeReport(successID, successID+1)); err != nil {
			return nil, err
		}
		if _, err := events.InsertOne(sc, makeEvent(successID, successID+1)); err != nil {
			return nil, err
		}
		return nil, nil
	}); err != nil {
		return fmt.Errorf("success transaction: %w", err)
	}

	if err := checkPair(ctx, reports, events, successID, 1); err != nil {
		return fmt.Errorf("success verification: %w", err)
	}
	fmt.Println("SUCCESS: diagnostic report and event committed")

	// Сценарий 2. Вторая операция нарушает валидатор.
	// Первая операция должна быть отменена вместе со всей транзакцией.
	rollbackID := baseID + 10
	if err := checkPair(ctx, reports, events, rollbackID, 0); err != nil {
		return fmt.Errorf("rollback initial state: %w", err)
	}
	fmt.Println("BEFORE: reports=0 events=0")
	firstWriteVerified := false
	rollbackErr := runTransaction(ctx, client, func(sc mongo.SessionContext) (interface{}, error) {
		if _, err := reports.InsertOne(sc, makeReport(rollbackID, rollbackID+1)); err != nil {
			return nil, err
		}
		// Собственная первая запись уже видна внутри той же транзакции.
		count, err := reports.CountDocuments(sc, bson.M{"pg_request_id": rollbackID})
		if err != nil {
			return nil, err
		}
		if count != 1 {
			return nil, fmt.Errorf("first write not visible: reports=%d", count)
		}
		firstWriteVerified = true
		fmt.Println("INSIDE TRANSACTION: reports=1")

		invalidEvent := bson.M{
			"pg_request_id": rollbackID,
			"type":          "diagnosis_recorded",
			"created_at":    time.Now(),
			// Намеренно отсутствует обязательное поле author.
			"payload": bson.M{
				"pg_diagnosis_id": rollbackID + 1,
				"revision":        int64(1),
			},
		}
		_, err = events.InsertOne(sc, invalidEvent)
		return nil, err
	})
	if rollbackErr == nil {
		return fmt.Errorf("rollback scenario: expected validation error, got nil")
	}

	if !firstWriteVerified {
		return fmt.Errorf("rollback scenario: first write was not verified")
	}
	var writeErr mongo.WriteException
	if !errors.As(rollbackErr, &writeErr) || !writeErr.HasErrorCode(121) {
		return fmt.Errorf("expected document validation error 121: %w", rollbackErr)
	}
	fmt.Println("EXPECTED ERROR: document validation failed, code=121")
	if err := checkPair(ctx, reports, events, rollbackID, 0); err != nil {
		return fmt.Errorf("rollback verification: %w", err)
	}
	fmt.Println("AFTER ROLLBACK: reports=0 events=0")
	fmt.Println("PASS: partial result is absent")
	fmt.Printf("ROLLBACK: transaction aborted after validation error: %v\n", rollbackErr)

	// Сценарий 3. Искусственно моделируем временную ошибку.
	// WithTransaction должен повторить callback.
	retryID := baseID + 20
	attempts := 0

	err := runTransaction(ctx, client, func(sc mongo.SessionContext) (interface{}, error) {
		attempts++

		if attempts == 1 {
			return nil, mongo.CommandError{
				Code:    251,
				Message: "simulated transient transaction error",
				Labels:  []string{"TransientTransactionError"},
			}
		}

		if _, err := reports.InsertOne(sc, makeReport(retryID, retryID+1)); err != nil {
			return nil, err
		}
		if _, err := events.InsertOne(sc, makeEvent(retryID, retryID+1)); err != nil {
			return nil, err
		}
		return nil, nil
	})
	if err != nil {
		return fmt.Errorf("retry transaction: %w", err)
	}

	if attempts < 2 {
		return fmt.Errorf("retry verification: expected at least 2 attempts, got %d", attempts)
	}
	if err := checkPair(ctx, reports, events, retryID, 1); err != nil {
		return fmt.Errorf("retry verification: %w", err)
	}

	fmt.Printf("RETRY: transaction callback executed %d times; both documents committed\n", attempts)

	return nil
}

func runTransaction(
	ctx context.Context,
	client *mongo.Client,
	callback func(mongo.SessionContext) (interface{}, error),
) error {
	session, err := client.StartSession()
	if err != nil {
		return err
	}
	defer session.EndSession(ctx)

	_, err = session.WithTransaction(ctx, callback)
	return err
}

func makeReport(requestID, diagnosisID int64) bson.M {
	return bson.M{
		"pg_request_id":   requestID,
		"pg_diagnosis_id": diagnosisID,
		"revision":        int64(1),
		"kind":            "initial",
		"checks": bson.A{
			bson.M{"name": "power_test", "passed": true},
		},
		"found_faults": bson.A{},
		"attachments":  bson.A{},
	}
}

func makeEvent(requestID, diagnosisID int64) bson.M {
	return bson.M{
		"pg_request_id": requestID,
		"type":          "diagnosis_recorded",
		"created_at":    time.Now(),
		"author": bson.M{
			"pg_employee_id": int64(1),
		},
		"payload": bson.M{
			"pg_diagnosis_id": diagnosisID,
			"revision":        int64(1),
			"kind":            "initial",
		},
	}
}

func checkPair(
	ctx context.Context,
	reports, events *mongo.Collection,
	requestID int64,
	expected int64,
) error {
	reportCount, err := reports.CountDocuments(ctx, bson.M{"pg_request_id": requestID})
	if err != nil {
		return err
	}

	eventCount, err := events.CountDocuments(ctx, bson.M{"pg_request_id": requestID})
	if err != nil {
		return err
	}

	if reportCount != expected || eventCount != expected {
		return fmt.Errorf(
			"unexpected document counts: reports=%d events=%d expected=%d",
			reportCount, eventCount, expected,
		)
	}
	return nil
}
