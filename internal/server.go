package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"

	productProto "github.com/leonvanderhaeghen/go-grpc/pkg/product/v1"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

var collection *mongo.Collection

type server struct{

	productProto.UnimplementedProductConfigFetchServiceServer
}

type Product struct {
	Id      string 			   `bson:"_id,omitempty"`
	Name 	string             `bson:"name"`
	Price  	float32            `bson:"price"`
	Tags    string             `bson:"tags"`
	Barcode	string             `bson:"barcode"`
}

func main() {
	// if we crash the go code, we get the file name and line number
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	listener, err := net.Listen("tcp", "0.0.0.0:50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	fmt.Print("Server started")

	// connect to MongoDB
	client, err := mongo.NewClient(options.Client().ApplyURI("mongodb+srv://leonvanderhaeghen:EnagMsC8j00X1C8f@productscluster0.uw7owvj.mongodb.net/?retryWrites=true&w=majority"))
	fmt.Println(" mongodb connection opend")
	if err != nil {
		log.Fatal(err)
	}
	err = client.Connect(context.TODO())
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(" passed error checksd")

	collection = client.Database("myFirstDatabase").Collection("product")
	fmt.Println(" opend collection")

	s := grpc.NewServer()
	productProto.RegisterProductConfigFetchServiceServer(s, &server{})
	fmt.Println(" register server")

	//blogpb.RegisterBlogServiceServer(s, &server{})

	if err := s.Serve(listener); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}

	// goroutine for listener
	go func() {
		fmt.Printf("Server listening on port 50051 \n")
		if err := s.Serve(listener); err != nil {
			log.Fatalf("failed to serve: %v", err)
		}
	}()

	// wait for control C to exit
	ch := make(chan os.Signal, 1)

	// We'll accept graceful shutdowns when quit via SIGINT (Ctrl+C)
	// SIGKILL, SIGQUIT or SIGTERM (Ctrl+/) will not be caught.
	signal.Notify(ch, os.Interrupt)

	// Block until a signal is received
	<-ch

	fmt.Println("Closing MongoDB Connection")
	if err := client.Disconnect(context.TODO()); err != nil {
		log.Fatalf("Error on disconnection with MongoDB : %v", err)
	}

	fmt.Println("Stopping the server")
	s.Stop()
	fmt.Println("Closing the listener")
	listener.Close()
	fmt.Println("End of program")
}

func (*server) CreateProduct(ctx context.Context, req *productProto.CreateProductRequest) (*productProto.CreateProductResponse, error) {
	fmt.Println("Create product request")
	value := req.GetValues()

	data := Product{
		Id:	value.GetId(),
		Name: value.GetName(),
		Price: value.GetPrice(),
		Tags: value.GetTags(),
		Barcode: value.GetBarcode(),
	}

	_, err := collection.InsertOne(ctx, data)
	if err != nil {
		return nil, status.Errorf(
			codes.Internal,
			fmt.Sprintf("Internal error: %v", err),
		)
	}

	/*oid, ok := res.InsertedID.(primitive.ObjectID)
	if !ok {
		return nil, status.Errorf(
			codes.Internal,
			fmt.Sprintf("Cannot convert to ObjectID"),
		)
	}*/

	return &productProto.CreateProductResponse{
		Values: &productProto.Product{
			Id:	value.GetId(),
			Name: value.GetName(),
			Price: value.GetPrice(),
			Tags: value.GetTags(),
			Barcode: value.GetBarcode(),
		},
	}, nil
}