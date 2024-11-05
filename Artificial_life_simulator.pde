// Import necessary libraries
import controlP5.*;
import java.util.ArrayList;
import java.util.List;
import java.util.HashMap;
import java.util.Map;
import processing.core.PVector;
import processing.sound.*;

// Global variables
ControlP5 cp5;
PVector camPos = new PVector(0, 0);
float zoomLevel = 1.0;
boolean isLoading = false;
float loadProgress = 0.0;
boolean isWorldEmpty = false;
int generationCount = 0;
List<Creature> creatures = new ArrayList<>();
List<Food> foods = new ArrayList<>();
List<Obstacle> obstacles = new ArrayList<>();
List<Virus> viruses = new ArrayList<>();
Map<String, SavedCreature> savedCreatures = new HashMap<>();
Creature selectedCreature = null;
float dayCycle = 0;
boolean isRaining = false;
float rainTimer = 0;

// Simulation speed variables
float simulationSpeed = 1.0;
boolean isPaused = false;

// Sound variables for ambience
SoundFile ambientSound;
float ambientVolume = 0.5;

// Application states
final int STATE_MAIN_MENU = 0;
final int STATE_SIMULATION = 1;
final int STATE_ARCHIVE = 2;
final int STATE_CONTROLS = 3;
int currentState = STATE_MAIN_MENU;

// Control Panel class for button management
class ControlPanel {
    HashMap<String, Button> buttons = new HashMap<>();

    void addButton(String label, int x, int y, int width, int height, CallbackListener callback) {
        Button button = cp5.addButton(label).setPosition(x, y).setSize(width, height).onClick(callback);
        buttons.put(label, button);
    }

    void show() {
        for (Button button : buttons.values()) button.show();
    }

    void hide() {
        for (Button button : buttons.values()) button.hide();
    }
}

ControlPanel mainMenuPanel = new ControlPanel();
ControlPanel simulationPanel = new ControlPanel();

// Environment class for day-night cycle and weather effects
class Environment {
    float cycleSpeed = 0.001;

    void updateCycle() {
        dayCycle += cycleSpeed * simulationSpeed;
        if (dayCycle >= 1) dayCycle = 0;
        if (rainTimer <= 0 && random(1) < 0.001 * simulationSpeed) {
            isRaining = true;
            rainTimer = random(2000, 5000);
        } else if (isRaining) {
            rainTimer--;
            if (rainTimer <= 0) {
                isRaining = false;
            }
        }
    }

    int getCurrentSkyColor() {
        return lerpColor(color(50, 50, 100), color(100, 100, 250), abs(sin(dayCycle * PI)));
    }
}

Environment environment = new Environment();

// Gene class with mutation and crossbreeding functionality
class Gene {
    float size, speed, colorR, colorG, colorB;
    float lifespan, metabolism, reproductionRate, mutationChance;
    float visionRange, aggressiveness, resilience;

    Gene(float size, float speed, float colorR, float colorG, float colorB, float lifespan,
         float metabolism, float reproductionRate, float mutationChance, float visionRange,
         float aggressiveness, float resilience) {
        this.size = size;
        this.speed = speed;
        this.colorR = colorR;
        this.colorG = colorG;
        this.colorB = colorB;
        this.lifespan = lifespan;
        this.metabolism = metabolism;
        this.reproductionRate = reproductionRate;
        this.mutationChance = mutationChance;
        this.visionRange = visionRange;
        this.aggressiveness = aggressiveness;
        this.resilience = resilience;
    }

    Gene mutate() {
        return new Gene(
            constrain(size + random(-0.05, 0.05), 1, 5),
            constrain(speed + random(-0.05, 0.05), 0.5, 3),
            constrain(colorR + random(-20, 20), 50, 255),
            constrain(colorG + random(-20, 20), 50, 255),
            constrain(colorB + random(-20, 20), 50, 255),
            constrain(lifespan + random(-5, 5), 50, 200),
            constrain(metabolism + random(-0.02, 0.02), 0.1, 1),
            constrain(reproductionRate + random(-0.01, 0.01), 0.1, 1),
            constrain(mutationChance + random(-0.01, 0.01), 0.05, 0.3),
            constrain(visionRange + random(-5, 5), 20, 200),
            constrain(aggressiveness + random(-0.1, 0.1), 0, 1),
            constrain(resilience + random(-0.1, 0.1), 0, 1)
        );
    }
}

// Creature class for individual creatures in the simulation
class Creature {
    PVector pos, vel;
    Gene genes;
    NeuralNetwork brain;
    float energy, age;
    boolean isDead = false;
    boolean isAggressive;
    int creatureType;
    color displayColor;

    Creature(Gene genes) {
        this.genes = (genes != null) ? genes : randomGenes();
        this.brain = new NeuralNetwork();
        pos = new PVector(random(width), random(height));
        vel = PVector.random2D().mult(this.genes.speed);
        energy = 200;
        age = 0;
        isAggressive = this.genes.aggressiveness > 0.5;
        creatureType = (int) random(3);
        displayColor = color(this.genes.colorR, this.genes.colorG, this.genes.colorB, 200);
    }

    Gene randomGenes() {
        return new Gene(
            random(1, 5), random(0.5, 3), random(50, 255), random(50, 255), random(50, 255),
            random(50, 200), random(0.1, 1), random(0.1, 1), random(0.05, 0.3),
            random(20, 100), random(0, 1), random(0.2, 1)
        );
    }

    void update() {
        if (isPaused || isDead || age > genes.lifespan || energy <= 0) {
            isDead = true;
            return;
        }
        
        age += 1 * simulationSpeed;
        energy -= genes.metabolism * 0.1 * simulationSpeed;
        
        if (isRaining) energy -= 0.05 * simulationSpeed;
        
        interactWithFood();
        interactWithCreatures();
        interactWithViruses();

        float decision = brain.decideAction(1, -1);
        vel.rotate(decision * 0.1);
        pos.add(vel.mult(simulationSpeed));
        pos.x = constrain(pos.x, 0, width);
        pos.y = constrain(pos.y, 0, height);

        if (!isWorldEmpty && random(1) < genes.reproductionRate && energy > 150) {
            reproduce();
        }
    }

    void interactWithFood() {
        for (Food food : foods) {
            if (dist(pos.x, pos.y, food.pos.x, food.pos.y) < genes.visionRange) {
                energy += food.nutrition;
                food.respawn();
            }
        }
    }

    void interactWithCreatures() {
        for (Creature other : creatures) {
            if (other != this && dist(pos.x, pos.y, other.pos.x, other.pos.y) < genes.visionRange) {
                if (creatureType == 1 && other.creatureType == 0) {
                    other.energy -= genes.aggressiveness * 10;
                } else if (creatureType == 2 && random(1) > 0.5) {
                    other.energy -= genes.aggressiveness * 5;
                }
            }
        }
    }

    void interactWithViruses() {
        for (Virus virus : viruses) {
            if (virus.active && dist(pos.x, pos.y, virus.pos.x, virus.pos.y) < virus.infectionRange) {
                virus.infect(this);
            }
        }
    }

    void reproduce() {
        creatures.add(new Creature(genes.mutate()));
        energy -= 100;
    }

    void display() {
        if (this == selectedCreature) {
            stroke(255, 255, 0);
            strokeWeight(3);
        } else {
            noStroke();
        }
        
        fill(displayColor);
        ellipse(pos.x, pos.y, genes.size * 10, genes.size * 10);
        
        if (this == selectedCreature) {
            fill(0, 255, 0);
            rect(pos.x - genes.size * 5, pos.y - genes.size * 6, genes.size * 10 * (energy / 200), 3);
        }
        
        strokeWeight(1);
        noStroke();
    }
}

// SavedCreature class for storing creatures in the archive
class SavedCreature {
    String name;
    Gene genes;
    NeuralNetwork brain;

    SavedCreature(String name, Gene genes, NeuralNetwork brain) {
        this.name = name;
        this.genes = genes;
        this.brain = brain;
    }
}

// Virus class for infecting creatures
class Virus {
    PVector pos;
    float infectionRange;
    boolean active;

    Virus() {
        pos = new PVector(random(width), random(height));
        infectionRange = random(20, 50);
        active = true;
    }

    void infect(Creature target) {
        if (dist(pos.x, pos.y, target.pos.x, target.pos.y) < infectionRange) {
            target.genes = target.genes.mutate(); // Mutate genes upon infection
            active = false;
        }
    }

    void display() {
        if (active) {
            fill(150, 0, 255, 150);
            ellipse(pos.x, pos.y, infectionRange, infectionRange);
        }
    }
}

// Obstacle class
class Obstacle {
    PVector pos;
    float size;

    Obstacle(float x, float y, float size) {
        pos = new PVector(x, y);
        this.size = size;
    }

    void display() {
        fill(100, 100, 100);
        ellipse(pos.x, pos.y, size * 2, size * 2);
    }
}

// Food class
class Food {
    PVector pos;
    float nutrition;

    Food() {
        respawn();
    }

    void respawn() {
        pos = new PVector(random(width), random(height));
        nutrition = random(10, 20);
    }

    void display() {
        fill(100, 255, 100);
        ellipse(pos.x, pos.y, 10, 10);
    }
}

// NeuralNetwork class for decision-making
class NeuralNetwork {
    float responseToFood, responseToCreatures;

    NeuralNetwork() {
        responseToFood = random(-1, 1);
        responseToCreatures = random(-1, 1);
    }

    float decideAction(float foodInput, float creatureInput) {
        return map(responseToFood * foodInput + responseToCreatures * creatureInput, -1, 1, -0.5, 0.5);
    }
}

// Setup and Main Functions
void setup() {
    size(1600, 900);
    cp5 = new ControlP5(this);
    setupMainMenu();
    setupSimulationControls();
    ambientSound = new SoundFile(this, "Reflection of Times.wav");
    if (ambientSound != null) {
        ambientSound.loop();
        ambientSound.amp(ambientVolume);
    }

    for (int i = 0; i < 10; i++) obstacles.add(new Obstacle(random(width), random(height), random(20, 50)));
    for (int i = 0; i < 100; i++) foods.add(new Food());
    for (int i = 0; i < 3; i++) viruses.add(new Virus());
}

void setupMainMenu() {
    mainMenuPanel.addButton("Start Simulation", width / 2 - 75, height / 2, 150, 40, event -> {
        isWorldEmpty = false;
        initializeSimulation();
        currentState = STATE_SIMULATION;
        mainMenuPanel.hide();
        simulationPanel.show();
    });
    mainMenuPanel.addButton("Creature Archive", width / 2 - 75, height / 2 + 50, 150, 40, event -> {
        currentState = STATE_ARCHIVE;
        mainMenuPanel.hide();
    });
    mainMenuPanel.addButton("Controls", width / 2 - 75, height / 2 + 100, 150, 40, event -> {
        currentState = STATE_CONTROLS;
        mainMenuPanel.hide();
    });
    mainMenuPanel.addButton("Exit", width / 2 - 75, height / 2 + 150, 150, 40, event -> exit());
}

// Setting up simulation-specific controls
void setupSimulationControls() {
    simulationPanel.addButton("Pause", 20, height - 50, 80, 30, event -> isPaused = !isPaused);
    simulationPanel.addButton("Speed Up", 110, height - 50, 80, 30, event -> simulationSpeed = min(simulationSpeed + 0.5, 3.0));
    simulationPanel.addButton("Slow Down", 200, height - 50, 80, 30, event -> simulationSpeed = max(simulationSpeed - 0.5, 0.5));
    simulationPanel.addButton("Main Menu", 290, height - 50, 100, 30, event -> {
        currentState = STATE_MAIN_MENU;
        mainMenuPanel.show();
        simulationPanel.hide();
    });
}

void initializeSimulation() {
    generationCount = 0;
    creatures.clear();
    foods.clear();
    obstacles.clear();

    for (int i = 0; i < 50; i++) creatures.add(new Creature(null));
    for (int i = 0; i < 100; i++) foods.add(new Food());
    for (int i = 0; i < 10; i++) obstacles.add(new Obstacle(random(width), random(height), random(20, 50)));
}

void runSimulation() {
    applyCameraTransform();

    for (Obstacle obstacle : obstacles) obstacle.display();
    updateAndDisplayCreatures();
    updateAndDisplayFood();
    for (Virus virus : viruses) virus.display();

    resetCameraTransform();

    if (ambientSound != null && !ambientSound.isPlaying()) {
        ambientSound.loop();
    }
}

void updateAndDisplayCreatures() {
    for (int i = creatures.size() - 1; i >= 0; i--) {
        Creature creature = creatures.get(i);
        creature.update();
        if (creature.isDead) {
            creatures.remove(i);
        } else {
            creature.display();
        }
    }
}

void updateAndDisplayFood() {
    for (Food food : foods) food.display();
}

// Camera functions for zoom and panning
void applyCameraTransform() {
    translate(width / 2, height / 2);
    scale(zoomLevel);
    translate(-camPos.x, -camPos.y);
}

void resetCameraTransform() {
    resetMatrix();
}

void mouseWheel(MouseEvent event) {
    float e = event.getCount();
    zoomLevel = constrain(zoomLevel - e * 0.05, 0.5, 2.5);
}

void keyPressed() {
    float panSpeed = 10 / zoomLevel;
    if (keyCode == UP) camPos.y -= panSpeed;
    if (keyCode == DOWN) camPos.y += panSpeed;
    if (keyCode == LEFT) camPos.x -= panSpeed;
    if (keyCode == RIGHT) camPos.x += panSpeed;

    if (key == 'M' || key == 'm') {
        currentState = STATE_MAIN_MENU;
        mainMenuPanel.show();
        simulationPanel.hide();
    } else if (key == 'R' || key == 'r') {
        initializeSimulation();
    } else if (key == 'S' || key == 's' && selectedCreature != null) {
        saveToArchive(selectedCreature);
    } else if (key == 'L' || key == 'l') {
        loadRandomCreatureFromArchive();
    }
}

void displayHUD() {
    fill(255);
    textSize(16);
    text("Generation: " + generationCount, 10, 20);
    text("Population: " + creatures.size(), 10, 40);
    text("Food Count: " + foods.size(), 10, 60);
    text("Speed: " + nf(simulationSpeed, 1, 1) + "x", 10, 80);
    if (isRaining) text("Weather: Rain", 10, 100);
}

void displayCreatureInfo() {
    fill(255);
    textSize(14);
    textAlign(LEFT);
    text("Size: " + nf(selectedCreature.genes.size, 1, 2), width - 150, 20);
    text("Speed: " + nf(selectedCreature.genes.speed, 1, 2), width - 150, 40);
    text("Color: " + selectedCreature.genes.colorR + ", " + selectedCreature.genes.colorG + ", " + selectedCreature.genes.colorB, width - 150, 60);
    text("Lifespan: " + nf(selectedCreature.genes.lifespan, 1, 2), width - 150, 80);
    text("Energy: " + nf(selectedCreature.energy, 1, 2), width - 150, 100);
    text("Type: " + selectedCreature.creatureType, width - 150, 120);
}

void mousePressed() {
    PVector mousePos = new PVector(mouseX, mouseY);
    selectedCreature = null;
    for (Creature creature : creatures) {
        if (dist(mousePos.x, mousePos.y, creature.pos.x, creature.pos.y) < creature.genes.size * 10) {
            selectedCreature = creature;
            break;
        }
    }
}

void saveToArchive(Creature creature) {
    String name = "Creature_" + generationCount + "_" + millis();
    savedCreatures.put(name, new SavedCreature(name, creature.genes, creature.brain));
    println("Saved " + name + " to archive.");
}

void loadRandomCreatureFromArchive() {
    if (!savedCreatures.isEmpty()) {
        Gene randomGene = savedCreatures.values().iterator().next().genes;
        creatures.add(new Creature(randomGene));
    }
}

void draw() {
    background(environment.getCurrentSkyColor());
    environment.updateCycle();

    if (currentState == STATE_SIMULATION && !isPaused) {
        runSimulation();
    } else if (isPaused) {
        fill(255, 100, 100);
        textAlign(CENTER);
        text("Simulation Paused", width / 2, height / 2);
    }

    displayHUD();
    if (selectedCreature != null) displayCreatureInfo();
}

void displayMainMenu() {
    background(20, 40, 70);
    textAlign(CENTER);
    textSize(32);
    fill(255);
    text("Evolution Simulator", width / 2, height / 2 - 150);
    textSize(20);
    fill(180);
    text("Developer: Christopher J Boardman", width / 2, height / 2 - 100);
    text("Instagram: @Wigan96", width / 2, height / 2 - 70);
    mainMenuPanel.show();
}
