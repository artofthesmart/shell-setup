<?php
header("Cache-Control: no-cache, must-revalidate");

$managed_containers = ['open-webui', 'ollama', 'invokeai', 'llama-cpp-1', 'llama-cpp-2'];

function get_container_states() {
    global $managed_containers;
    $states = [];
    $output = shell_exec("docker ps -a --format '{{.Names}}|{{.State}}'");
    if ($output) {
        $lines = explode("\n", trim($output));
        foreach ($lines as $line) {
            $parts = explode("|", $line);
            if (count($parts) == 2) {
                $name = $parts[0];
                $state = $parts[1];
                if (in_array($name, $managed_containers)) {
                    $states[$name] = ($state === 'running');
                }
            }
        }
    }
    // Default any missing to false
    foreach ($managed_containers as $c) {
        if (!isset($states[$c])) {
            $states[$c] = false;
        }
    }
    return $states;
}

function process_request() {
    global $managed_containers;

    // Handle JSON API payload
    $content_type = isset($_SERVER["CONTENT_TYPE"]) ? trim($_SERVER["CONTENT_TYPE"]) : '';
    if ($content_type === "application/json") {
        $data = json_decode(file_get_contents("php://input"), true);
        if (isset($data['action']) && isset($data['container']) && in_array($data['container'], $managed_containers)) {
            $action = $data['action'] === 'start' ? 'start' : 'stop';
            shell_exec("docker {$action} " . escapeshellarg($data['container']));
            echo json_encode(["status" => "success", "container" => $data['container'], "action" => $action]);
        } else {
            http_response_code(400);
            echo json_encode(["status" => "error", "message" => "Invalid request"]);
        }
        exit;
    }

    // Handle Form Submission
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $current_states = get_container_states();
        foreach ($managed_containers as $container) {
            $requested_state = isset($_POST[$container]) && $_POST[$container] === 'on';
            if ($requested_state && !$current_states[$container]) {
                shell_exec("docker start " . escapeshellarg($container));
            } elseif (!$requested_state && $current_states[$container]) {
                shell_exec("docker stop " . escapeshellarg($container));
            }
        }
        // Redirect to avoid form resubmission
        header("Location: " . $_SERVER['PHP_SELF']);
        exit;
    }
}

process_request();
$states = get_container_states();
?>
<!DOCTYPE html>
<html>
<head>
    <title>GPU Container Manager</title>
    <style>
        body { font-family: sans-serif; margin: 40px; background: #f4f4f9; color: #333; }
        .container { max-width: 600px; margin: 0 auto; background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        h1 { font-size: 24px; margin-bottom: 20px; }
        .item { display: flex; justify-content: space-between; align-items: center; padding: 10px 0; border-bottom: 1px solid #eee; }
        .item:last-child { border-bottom: none; }
        .switch { position: relative; display: inline-block; width: 60px; height: 34px; }
        .switch input { opacity: 0; width: 0; height: 0; }
        .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #ccc; transition: .4s; border-radius: 34px; }
        .slider:before { position: absolute; content: ""; height: 26px; width: 26px; left: 4px; bottom: 4px; background-color: white; transition: .4s; border-radius: 50%; }
        input:checked + .slider { background-color: #2196F3; }
        input:focus + .slider { box-shadow: 0 0 1px #2196F3; }
        input:checked + .slider:before { transform: translateX(26px); }
        .btn { display: block; width: 100%; padding: 15px; margin-top: 20px; background: #4CAF50; color: white; border: none; border-radius: 4px; font-size: 16px; cursor: pointer; }
        .btn:hover { background: #45a049; }
    </style>
</head>
<body>
    <div class="container">
        <h1>GPU Container Manager</h1>
        <p>Toggle your LLM services to free up VRAM.</p>
        <form method="POST">
            <?php foreach ($states as $name => $isRunning): ?>
            <div class="item">
                <span><strong><?php echo htmlspecialchars($name); ?></strong></span>
                <label class="switch">
                    <input type="checkbox" name="<?php echo htmlspecialchars($name); ?>" <?php echo $isRunning ? 'checked' : ''; ?>>
                    <span class="slider"></span>
                </label>
            </div>
            <?php endforeach; ?>
            <button class="btn" type="submit">Apply Changes</button>
        </form>
    </div>
</body>
</html>
