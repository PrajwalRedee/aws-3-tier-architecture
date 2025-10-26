#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1
set -x

echo "Starting user-data at $(date)"

# Install Apache
dnf update -y
dnf install -y httpd

systemctl enable httpd
systemctl start httpd

# Function to get metadata with IMDSv2 and retry logic
get_metadata() {
  local path=$1
  local max_attempts=10
  
  for i in $(seq 1 $max_attempts); do
    # Get IMDSv2 token
    TOKEN=$(curl -s -f -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
    
    if [ -n "$TOKEN" ]; then
      # Fetch metadata using token
      RESULT=$(curl -s -f -H "X-aws-ec2-metadata-token: $TOKEN" \
        "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null)
      
      if [ -n "$RESULT" ]; then
        echo "$RESULT"
        return 0
      fi
    fi
    
    echo "Retry $i/$max_attempts for $path"
    sleep 2
  done
  
  echo "Unavailable"
  return 1
}

# Get instance metadata
INSTANCE_ID=$(get_metadata "instance-id")
AZ=$(get_metadata "placement/availability-zone")

echo "Instance ID: $INSTANCE_ID"
echo "Availability Zone: $AZ"

# Create web page (note: ${region} will be replaced by Terraform templatefile())
cat <<'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>3-Tier Architecture</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            text-align: center;
            padding: 50px;
            margin: 0;
        }
        .container {
            background: white;
            border-radius: 10px;
            padding: 40px;
            max-width: 600px;
            margin: 0 auto;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        h1 { color: #333; margin-bottom: 20px; }
        .info { 
            background: #f8f9fa; 
            padding: 15px; 
            margin: 15px 0; 
            border-radius: 5px;
            border-left: 4px solid #667eea;
        }
        .success { 
            background: #d4edda; 
            color: #155724; 
            padding: 15px; 
            border-radius: 5px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 3-Tier Architecture - Web Tier</h1>
        <h2>Hello from Instance</h2>
        
        <div class="info">
            <strong>Instance ID:</strong> INSTANCE_ID_PLACEHOLDER
        </div>
        
        <div class="info">
            <strong>Availability Zone:</strong> AZ_PLACEHOLDER
        </div>
        
        <div class="info">
            <strong>Region:</strong> REGION_PLACEHOLDER
        </div>
        
        <div class="success">
            ✅ Apache running successfully on Amazon Linux 2023!
        </div>
    </div>
</body>
</html>
EOF

# Replace placeholders with actual values
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /var/www/html/index.html
sed -i "s/AZ_PLACEHOLDER/$AZ/g" /var/www/html/index.html
sed -i "s/REGION_PLACEHOLDER/${region}/g" /var/www/html/index.html

# Restart Apache
systemctl restart httpd

echo "User data completed at $(date)"