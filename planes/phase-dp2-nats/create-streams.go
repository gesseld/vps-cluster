package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/nats-io/nats.go"
)

func main() {
	// Connect to NATS
	nc, err := nats.Connect("nats://nats:4222")
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer nc.Close()

	// Create JetStream context
	js, err := nc.JetStream()
	if err != nil {
		log.Fatalf("Failed to create JetStream context: %v", err)
	}

	// Stream configurations
	streams := []nats.StreamConfig{
		{
			Name:        "DOCUMENTS",
			Subjects:    []string{"data.doc.>"},
			Retention:   nats.WorkQueuePolicy,
			MaxMsgs:     100000,
			MaxBytes:    5 * 1024 * 1024 * 1024, // 5GB
			Storage:     nats.FileStorage,
			NumReplicas: 1,
			Discard:     nats.DiscardOldPolicy,
			Description: "Document processing stream with work queue retention",
		},
		{
			Name:        "EXECUTION",
			Subjects:    []string{"exec.task.>"},
			Retention:   nats.InterestPolicy,
			MaxMsgs:     50000,
			MaxBytes:    2 * 1024 * 1024 * 1024, // 2GB
			MaxAge:      24 * time.Hour,
			Storage:     nats.FileStorage,
			NumReplicas: 1,
			Discard:     nats.DiscardOldPolicy,
			Description: "Task execution stream with 24h retention, 2GB limit",
		},
		{
			Name:        "OBSERVABILITY",
			Subjects:    []string{"obs.metric.>"},
			Retention:   nats.LimitsPolicy,
			MaxBytes:    1 * 1024 * 1024 * 1024, // 1GB
			Storage:     nats.FileStorage,
			NumReplicas: 1,
			Discard:     nats.DiscardOldPolicy,
			Description: "Observability metrics stream with size limits",
		},
	}

	// Create each stream
	for _, stream := range streams {
		fmt.Printf("Creating stream: %s...\n", stream.Name)
		
		// Check if stream already exists
		info, err := js.StreamInfo(stream.Name)
		if err == nil && info != nil {
			fmt.Printf("  Stream %s already exists\n", stream.Name)
			continue
		}
		
		_, err = js.AddStream(&stream)
		if err != nil {
			fmt.Printf("  Error creating stream %s: %v\n", stream.Name, err)
			continue
		}
		fmt.Printf("  ✓ Created stream %s\n", stream.Name)
	}

	// Verify streams
	fmt.Println("\nVerifying streams...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	streamsInfo, err := js.StreamsInfo()
	if err != nil {
		log.Fatalf("Failed to get streams info: %v", err)
	}

	for _, s := range streamsInfo {
		fmt.Printf("  - %s: %d messages, %d bytes\n", s.Config.Name, s.State.Messages, s.State.Bytes)
	}

	fmt.Println("\nDone!")
}