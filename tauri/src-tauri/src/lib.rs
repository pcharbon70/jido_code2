use tauri::{WebviewUrl, WebviewWindowBuilder};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let handle = app.handle().clone();

            tauri::async_runtime::spawn(async move {
                if let Err(e) = start_backend(&handle).await {
                    eprintln!("Failed to start backend: {}", e);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

async fn start_backend(handle: &tauri::AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    use tauri_plugin_shell::ShellExt;

    println!("Starting Jido Code backend...");
    println!("Platform: {}", std::env::consts::OS);
    println!("Architecture: {}", std::env::consts::ARCH);

    let sidecar_command = handle
        .shell()
        .sidecar("jido_code_backend")?
        .env("PORT", "4000")
        .env("MIX_ENV", "prod")
        .env("BURRITO_TARGET", "tauri");

    let (_rx, _child) = sidecar_command.spawn()?;

    println!("Backend process started, waiting for it to be ready...");

    let mut attempts = 0;
    let max_attempts = 60;

    loop {
        attempts += 1;
        if attempts > max_attempts {
            return Err(
                format!("Backend failed to start after {} attempts", max_attempts).into(),
            );
        }

        match reqwest::get("http://localhost:4000").await {
            Ok(response)
                if response.status().is_success() || response.status().is_redirection() =>
            {
                println!("Backend is ready after {} attempts!", attempts);
                break;
            }
            Ok(response) => {
                println!(
                    "Backend responded with status: {} (attempt {})",
                    response.status(),
                    attempts
                );
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            }
            Err(e) => {
                if attempts % 5 == 0 {
                    println!(
                        "Waiting for backend... (attempt {}/{}): {}",
                        attempts, max_attempts, e
                    );
                }
                tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            }
        }
    }

    WebviewWindowBuilder::new(
        handle,
        "main",
        WebviewUrl::External("http://localhost:4000".parse().unwrap()),
    )
    .title("Jido Code")
    .inner_size(1400.0, 900.0)
    .center()
    .build()?;

    println!("Main window opened successfully");

    Ok(())
}
