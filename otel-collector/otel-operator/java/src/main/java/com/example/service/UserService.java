package com.example.service;

import com.example.model.User;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Simple service class for User operations with in-memory storage
 */
@Service
public class UserService {

    private static final Logger log = LoggerFactory.getLogger(UserService.class);
    
    private final Map<Long, User> users = new ConcurrentHashMap<>();
    private final AtomicLong idCounter = new AtomicLong(1);

    /**
     * Create a new user
     */
    public User createUser(User user) {
        log.info("Creating new user: {}", user.getUsername());
        
        // Check if username already exists
        if (users.values().stream().anyMatch(u -> u.getUsername().equals(user.getUsername()))) {
            throw new RuntimeException("Username already exists: " + user.getUsername());
        }
        
        // Check if email already exists
        if (users.values().stream().anyMatch(u -> u.getEmail().equals(user.getEmail()))) {
            throw new RuntimeException("Email already exists: " + user.getEmail());
        }
        
        // Set ID and timestamps
        user.setId(idCounter.getAndIncrement());
        user.setCreatedAt(LocalDateTime.now());
        user.setUpdatedAt(LocalDateTime.now());
        
        users.put(user.getId(), user);
        return user;
    }

    /**
     * Get all users
     */
    public List<User> getAllUsers() {
        log.info("Retrieving all users");
        return new ArrayList<>(users.values());
    }

    /**
     * Get user by ID
     */
    public Optional<User> getUserById(Long id) {
        log.info("Retrieving user by ID: {}", id);
        return Optional.ofNullable(users.get(id));
    }

    /**
     * Get user by username
     */
    public Optional<User> getUserByUsername(String username) {
        log.info("Retrieving user by username: {}", username);
        return users.values().stream()
                .filter(user -> user.getUsername().equals(username))
                .findFirst();
    }

    /**
     * Update user
     */
    public User updateUser(Long id, User userDetails) {
        log.info("Updating user with ID: {}", id);
        
        User existingUser = users.get(id);
        if (existingUser == null) {
            throw new RuntimeException("User not found with ID: " + id);
        }
        
        // Check if new username conflicts with existing users (excluding current user)
        boolean usernameExists = users.values().stream()
                .filter(user -> !user.getId().equals(id))
                .anyMatch(user -> user.getUsername().equals(userDetails.getUsername()));
        
        if (usernameExists) {
            throw new RuntimeException("Username already exists: " + userDetails.getUsername());
        }
        
        // Check if new email conflicts with existing users (excluding current user)
        boolean emailExists = users.values().stream()
                .filter(user -> !user.getId().equals(id))
                .anyMatch(user -> user.getEmail().equals(userDetails.getEmail()));
        
        if (emailExists) {
            throw new RuntimeException("Email already exists: " + userDetails.getEmail());
        }
        
        // Update user details
        existingUser.setUsername(userDetails.getUsername());
        existingUser.setEmail(userDetails.getEmail());
        existingUser.setFirstName(userDetails.getFirstName());
        existingUser.setLastName(userDetails.getLastName());
        existingUser.setUpdatedAt(LocalDateTime.now());
        
        return existingUser;
    }

    /**
     * Delete user
     */
    public void deleteUser(Long id) {
        log.info("Deleting user with ID: {}", id);
        
        if (!users.containsKey(id)) {
            throw new RuntimeException("User not found with ID: " + id);
        }
        
        users.remove(id);
    }

    /**
     * Search users by name
     */
    public List<User> searchUsersByName(String name) {
        log.info("Searching users by name: {}", name);
        return users.values().stream()
                .filter(user -> user.getFirstName().toLowerCase().contains(name.toLowerCase()) ||
                               user.getLastName().toLowerCase().contains(name.toLowerCase()))
                .toList();
    }

    /**
     * Get users by first name
     */
    public List<User> getUsersByFirstName(String firstName) {
        log.info("Retrieving users by first name: {}", firstName);
        return users.values().stream()
                .filter(user -> user.getFirstName().equalsIgnoreCase(firstName))
                .toList();
    }

    /**
     * Get users by last name
     */
    public List<User> getUsersByLastName(String lastName) {
        log.info("Retrieving users by last name: {}", lastName);
        return users.values().stream()
                .filter(user -> user.getLastName().equalsIgnoreCase(lastName))
                .toList();
    }

    /**
     * Initialize with sample data
     */
    public void initializeSampleData() {
        log.info("Initializing sample data...");
        
        createUser(new User("john_doe", "john.doe@example.com", "John", "Doe"));
        createUser(new User("jane_smith", "jane.smith@example.com", "Jane", "Smith"));
        createUser(new User("bob_wilson", "bob.wilson@example.com", "Bob", "Wilson"));
        createUser(new User("alice_johnson", "alice.johnson@example.com", "Alice", "Johnson"));
        createUser(new User("charlie_brown", "charlie.brown@example.com", "Charlie", "Brown"));
        
        log.info("Sample data initialized successfully. Created {} users.", users.size());
    }
} 