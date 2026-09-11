#!/bin/bash

################################################################################
# RAG Application AWS Cleanup Script
# This script safely removes all AWS resources created during RAG deployment
# Usage: ./cleanup.sh [--dry-run] [--force]
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
CLUSTER_NAME=${CLUSTER_NAME:-rag-cluster}
DRY_RUN=false
FORCE=false
CLEANUP_LOG="cleanup-$(date +%Y%m%d-%H%M%S).log"

# Global counters
CLEANUP_SUCCESS=0
CLEANUP_FAILED=0
CLEANUP_SKIPPED=0

################################################################################
# Utility Functions
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$CLEANUP_LOG"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1" | tee -a "$CLEANUP_LOG"
  ((CLEANUP_SUCCESS++))
}

log_error() {
  echo -e "${RED}[✗]${NC} $1" | tee -a "$CLEANUP_LOG"
  ((CLEANUP_FAILED++))
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $1" | tee -a "$CLEANUP_LOG"
  ((CLEANUP_SKIPPED++))
}

log_section() {
  echo -e "\n${BLUE}========================================${NC}" | tee -a "$CLEANUP_LOG"
  echo -e "${BLUE}$1${NC}" | tee -a "$CLEANUP_LOG"
  echo -e "${BLUE}========================================${NC}" | tee -a "$CLEANUP_LOG"
}

aws_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would execute: aws $@"
  else
    aws "$@"
  fi
}

confirm() {
  if [ "$FORCE" = true ]; then
    return 0
  fi
  
  local prompt="$1"
  local response
  read -p "$(echo -e ${YELLOW}$prompt${NC}) (yes/no): " response
  [ "$response" = "yes" ]
}

wait_for_resource() {
  local resource_type=$1
  local resource_id=$2
  local max_attempts=${3:-60}
  local attempt=0
  
  log_info "Waiting for $resource_type deletion: $resource_id"
  
  while [ $attempt -lt $max_attempts ]; do
    if ! aws ec2 describe-instances --instance-ids "$resource_id" --region "$AWS_REGION" 2>/dev/null | grep -q "running\|pending\|stopped\|stopping"; then
      return 0
    fi
    ((attempt++))
    sleep 2
  done
  
  return 1
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_ecs_service() {
  log_section "Cleaning up ECS Service"
  
  # Get service ARN
  local services=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --query 'serviceArns[]' --output text 2>/dev/null || echo "")
  
  if [ -z "$services" ]; then
    log_warning "No ECS services found in cluster $CLUSTER_NAME"
    return 0
  fi
  
  for service in $services; do
    log_info "Deleting ECS service: $service"
    if aws_cmd ecs delete-service --cluster "$CLUSTER_NAME" --service "$service" --force --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "ECS service deleted: $service"
    else
      log_error "Failed to delete ECS service: $service"
    fi
  done
}

cleanup_ecs_task_definitions() {
  log_section "Cleaning up ECS Task Definitions"
  
  local task_defs=$(aws ecs list-task-definitions --family-prefix "rag-app" --region "$AWS_REGION" --query 'taskDefinitionArns[]' --output text 2>/dev/null || echo "")
  
  if [ -z "$task_defs" ]; then
    log_warning "No ECS task definitions found"
    return 0
  fi
  
  for task_def in $task_defs; do
    log_info "Deregistering task definition: $task_def"
    if aws_cmd ecs deregister-task-definition --task-definition "$task_def" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "Task definition deregistered: $task_def"
    else
      log_error "Failed to deregister task definition: $task_def"
    fi
  done
}

cleanup_ecs_cluster() {
  log_section "Cleaning up ECS Cluster"
  
  # Check if cluster exists
  if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    log_warning "ECS cluster $CLUSTER_NAME not found"
    return 0
  fi
  
  log_info "Deleting ECS cluster: $CLUSTER_NAME"
  if aws_cmd ecs delete-cluster --cluster "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "ECS cluster deleted: $CLUSTER_NAME"
  else
    log_error "Failed to delete ECS cluster: $CLUSTER_NAME"
  fi
}

cleanup_alb() {
  log_section "Cleaning up Application Load Balancer"
  
  # Find ALB by name
  local alb_arn=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?LoadBalancerName=='rag-alb'].LoadBalancerArn" --output text 2>/dev/null || echo "")
  
  if [ -z "$alb_arn" ]; then
    log_warning "ALB 'rag-alb' not found"
    return 0
  fi
  
  log_info "Deleting ALB: $alb_arn"
  if aws_cmd elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "ALB deleted: $alb_arn"
  else
    log_error "Failed to delete ALB: $alb_arn"
  fi
}

cleanup_target_groups() {
  log_section "Cleaning up Target Groups"
  
  # Find target groups by name
  local tg_arns=$(aws elbv2 describe-target-groups --region "$AWS_REGION" --query "TargetGroups[?TargetGroupName=='rag-tg'].TargetGroupArn" --output text 2>/dev/null || echo "")
  
  if [ -z "$tg_arns" ]; then
    log_warning "Target group 'rag-tg' not found"
    return 0
  fi
  
  for tg_arn in $tg_arns; do
    log_info "Deleting target group: $tg_arn"
    if aws_cmd elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "Target group deleted: $tg_arn"
    else
      log_error "Failed to delete target group: $tg_arn"
    fi
  done
}

cleanup_rds() {
  log_section "Cleaning up RDS Database"
  
  local db_identifier="rag-db-instance"
  
  # Check if RDS exists
  if ! aws rds describe-db-instances --db-instance-identifier "$db_identifier" --region "$AWS_REGION" 2>/dev/null | grep -q "$db_identifier"; then
    log_warning "RDS instance '$db_identifier' not found"
    return 0
  fi
  
  log_info "Deleting RDS instance: $db_identifier"
  if aws_cmd rds delete-db-instance --db-instance-identifier "$db_identifier" --skip-final-snapshot --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "RDS instance deletion initiated: $db_identifier"
    log_info "Waiting for RDS deletion (this may take 5-10 minutes)..."
    sleep 30
  else
    log_error "Failed to delete RDS instance: $db_identifier"
  fi
}

cleanup_rds_subnet_group() {
  log_section "Cleaning up RDS Subnet Group"
  
  local sg_name="rag-db-subnet-group"
  
  # Check if subnet group exists
  if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$sg_name" --region "$AWS_REGION" 2>/dev/null | grep -q "$sg_name"; then
    log_warning "RDS subnet group '$sg_name' not found"
    return 0
  fi
  
  log_info "Deleting RDS subnet group: $sg_name"
  sleep 10  # Wait for RDS to be deleted
  
  if aws_cmd rds delete-db-subnet-group --db-subnet-group-name "$sg_name" --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "RDS subnet group deleted: $sg_name"
  else
    log_error "Failed to delete RDS subnet group: $sg_name"
  fi
}

cleanup_ec2_instances() {
  log_section "Cleaning up EC2 Instances"
  
  # Find instances by security group name
  local instance_ids=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*ollama*" "Name=instance-state-name,Values=running,stopped" --region "$AWS_REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
  
  if [ -z "$instance_ids" ]; then
    # Try to find by security group
    local sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=rag-ollama-sg" --region "$AWS_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
      instance_ids=$(aws ec2 describe-instances --filters "Name=instance.group-id,Values=$sg_id" "Name=instance-state-name,Values=running,stopped" --region "$AWS_REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
    fi
  fi
  
  if [ -z "$instance_ids" ]; then
    log_warning "No EC2 instances found for cleanup"
    return 0
  fi
  
  for instance_id in $instance_ids; do
    log_info "Terminating EC2 instance: $instance_id"
    if aws_cmd ec2 terminate-instances --instance-ids "$instance_id" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "EC2 instance termination initiated: $instance_id"
    else
      log_error "Failed to terminate EC2 instance: $instance_id"
    fi
  done
}

cleanup_nat_gateway() {
  log_section "Cleaning up NAT Gateway"
  
  # Find NAT gateways by tag
  local nat_ids=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=rag-nat" --region "$AWS_REGION" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null || echo "")
  
  if [ -z "$nat_ids" ]; then
    log_warning "No NAT gateways found for cleanup"
    return 0
  fi
  
  for nat_id in $nat_ids; do
    log_info "Deleting NAT Gateway: $nat_id"
    if aws_cmd ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "NAT Gateway deletion initiated: $nat_id"
    else
      log_error "Failed to delete NAT Gateway: $nat_id"
    fi
  done
  
  log_info "Waiting for NAT Gateway deletion (30 seconds)..."
  sleep 30
}

cleanup_elastic_ips() {
  log_section "Cleaning up Elastic IPs"
  
  # Find unassociated Elastic IPs
  local eip_allocs=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=rag-*" --region "$AWS_REGION" --query 'Addresses[].AllocationId' --output text 2>/dev/null || echo "")
  
  if [ -z "$eip_allocs" ]; then
    log_warning "No Elastic IPs found for cleanup"
    return 0
  fi
  
  for eip_alloc in $eip_allocs; do
    log_info "Releasing Elastic IP: $eip_alloc"
    if aws_cmd ec2 release-address --allocation-id "$eip_alloc" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "Elastic IP released: $eip_alloc"
    else
      log_error "Failed to release Elastic IP: $eip_alloc"
    fi
  done
}

cleanup_internet_gateway() {
  log_section "Cleaning up Internet Gateway"
  
  # Find IGW by tag
  local igw_ids=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=rag-igw" --region "$AWS_REGION" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
  
  if [ -z "$igw_ids" ]; then
    log_warning "No Internet Gateways found for cleanup"
    return 0
  fi
  
  for igw_id in $igw_ids; do
    # Find VPC associated with IGW
    local vpc_id=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" --region "$AWS_REGION" --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
      log_info "Detaching IGW from VPC: $igw_id from $vpc_id"
      if aws_cmd ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "IGW detached: $igw_id"
      else
        log_error "Failed to detach IGW: $igw_id"
      fi
    fi
    
    log_info "Deleting Internet Gateway: $igw_id"
    if aws_cmd ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "Internet Gateway deleted: $igw_id"
    else
      log_error "Failed to delete Internet Gateway: $igw_id"
    fi
  done
}

cleanup_security_groups() {
  log_section "Cleaning up Security Groups"
  
  local sg_names=("rag-alb-sg" "rag-fargate-sg" "rag-rds-sg" "rag-ollama-sg")
  
  for sg_name in "${sg_names[@]}"; do
    local sg_id=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --region "$AWS_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
      log_warning "Security group '$sg_name' not found"
      continue
    fi
    
    log_info "Deleting security group: $sg_name ($sg_id)"
    
    # Revoke all ingress rules first
    local rules=$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" --query 'SecurityGroups[0].IpPermissions[*].IpProtocol' --output text 2>/dev/null || echo "")
    
    if [ -n "$rules" ]; then
      log_info "Revoking ingress rules for $sg_id"
      aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions "IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]" --region "$AWS_REGION" > /dev/null 2>&1 || true
    fi
    
    # Revoke all egress rules
    local egress_rules=$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" --query 'SecurityGroups[0].IpPermissionsEgress[*].IpProtocol' --output text 2>/dev/null || echo "")
    
    if [ -n "$egress_rules" ]; then
      log_info "Revoking egress rules for $sg_id"
      aws ec2 revoke-security-group-egress --group-id "$sg_id" --ip-permissions "IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]" --region "$AWS_REGION" > /dev/null 2>&1 || true
    fi
    
    sleep 2
    
    if aws_cmd ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "Security group deleted: $sg_name"
    else
      log_error "Failed to delete security group: $sg_name ($sg_id)"
    fi
  done
}

cleanup_vpc() {
  log_section "Cleaning up VPC"
  
  local vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=rag-vpc" --region "$AWS_REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
  
  if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
    log_warning "VPC 'rag-vpc' not found"
    return 0
  fi
  
  log_info "Deleting VPC and associated resources: $vpc_id"
  
  # Delete route tables
  local rts=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --region "$AWS_REGION" --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text 2>/dev/null || echo "")
  
  for rt in $rts; do
    log_info "Deleting route table: $rt"
    aws_cmd ec2 delete-route-table --route-table-id "$rt" --region "$AWS_REGION" > /dev/null 2>&1 || true
  done
  
  # Delete subnets
  local subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$AWS_REGION" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
  
  for subnet in $subnets; do
    log_info "Deleting subnet: $subnet"
    aws_cmd ec2 delete-subnet --subnet-id "$subnet" --region "$AWS_REGION" > /dev/null 2>&1 || true
  done
  
  sleep 5
  
  # Delete VPC
  log_info "Deleting VPC: $vpc_id"
  if aws_cmd ec2 delete-vpc --vpc-id "$vpc_id" --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "VPC deleted: $vpc_id"
  else
    log_error "Failed to delete VPC: $vpc_id"
  fi
}

cleanup_ecr_repository() {
  log_section "Cleaning up ECR Repository"
  
  local repo_name="rag-app"
  
  # Check if repository exists
  if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" 2>/dev/null | grep -q "$repo_name"; then
    log_warning "ECR repository '$repo_name' not found"
    return 0
  fi
  
  log_info "Deleting ECR repository: $repo_name"
  if aws_cmd ecr delete-repository --repository-name "$repo_name" --force --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "ECR repository deleted: $repo_name"
  else
    log_error "Failed to delete ECR repository: $repo_name"
  fi
}

cleanup_iam_roles() {
  log_section "Cleaning up IAM Roles"
  
  local role_names=("rag-ecs-task-execution-role" "rag-ecs-task-role")
  
  for role_name in "${role_names[@]}"; do
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" 2>/dev/null | grep -q "$role_name"; then
      log_warning "IAM role '$role_name' not found"
      continue
    fi
    
    log_info "Cleaning up IAM role: $role_name"
    
    # Detach all attached policies
    local attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $attached_policies; do
      log_info "Detaching policy from $role_name: $policy_arn"
      aws_cmd iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" > /dev/null 2>&1 || true
    done
    
    # Delete inline policies
    local inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    
    for policy_name in $inline_policies; do
      log_info "Deleting inline policy from $role_name: $policy_name"
      aws_cmd iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" > /dev/null 2>&1 || true
    done
    
    sleep 2
    
    # Delete role
    log_info "Deleting IAM role: $role_name"
    if aws_cmd iam delete-role --role-name "$role_name" > /dev/null 2>&1; then
      log_success "IAM role deleted: $role_name"
    else
      log_error "Failed to delete IAM role: $role_name"
    fi
  done
}

cleanup_key_pairs() {
  log_section "Cleaning up EC2 Key Pairs"
  
  local key_name="rag-ollama-key"
  
  # Check if key pair exists
  if ! aws ec2 describe-key-pairs --key-names "$key_name" --region "$AWS_REGION" 2>/dev/null | grep -q "$key_name"; then
    log_warning "EC2 key pair '$key_name' not found"
    return 0
  fi
  
  log_info "Deleting EC2 key pair: $key_name"
  if aws_cmd ec2 delete-key-pair --key-name "$key_name" --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "EC2 key pair deleted: $key_name"
    
    # Delete local .pem file if exists
    if [ -f ~/.ssh/$key_name.pem ]; then
      log_info "Deleting local key file: ~/.ssh/$key_name.pem"
      rm -f ~/.ssh/$key_name.pem
      log_success "Local key file deleted"
    fi
  else
    log_error "Failed to delete EC2 key pair: $key_name"
  fi
}

cleanup_cloudwatch() {
  log_section "Cleaning up CloudWatch Resources"
  
  # Delete log group
  local log_group="/ecs/rag-app"
  
  if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$AWS_REGION" 2>/dev/null | grep -q "$log_group"; then
    log_info "Deleting CloudWatch log group: $log_group"
    if aws_cmd logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" > /dev/null 2>&1; then
      log_success "CloudWatch log group deleted: $log_group"
    else
      log_error "Failed to delete CloudWatch log group: $log_group"
    fi
  else
    log_warning "CloudWatch log group '$log_group' not found"
  fi
  
  # Delete alarms
  local alarm_names=("rag-high-cpu" "rag-unhealthy-targets")
  
  for alarm_name in "${alarm_names[@]}"; do
    log_info "Deleting CloudWatch alarm: $alarm_name"
    aws_cmd cloudwatch delete-alarms --alarm-names "$alarm_name" --region "$AWS_REGION" > /dev/null 2>&1 || true
  done
}

verify_cleanup() {
  log_section "Verifying Cleanup"
  
  local all_cleaned=true
  
  # Check ECS cluster
  if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null | grep -q "\"clusterName\": \"$CLUSTER_NAME\""; then
    log_warning "ECS cluster still exists: $CLUSTER_NAME"
    all_cleaned=false
  else
    log_success "ECS cluster cleanup verified"
  fi
  
  # Check VPC
  local vpc_exists=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=rag-vpc" --region "$AWS_REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
  
  if [ -n "$vpc_exists" ] && [ "$vpc_exists" != "None" ]; then
    log_warning "VPC still exists: $vpc_exists"
    all_cleaned=false
  else
    log_success "VPC cleanup verified"
  fi
  
  # Check RDS
  local rds_exists=$(aws rds describe-db-instances --db-instance-identifier "rag-db-instance" --region "$AWS_REGION" 2>/dev/null | grep -q "DBInstanceIdentifier" && echo "true" || echo "false")
  
  if [ "$rds_exists" = "true" ]; then
    log_warning "RDS instance still exists"
    all_cleaned=false
  else
    log_success "RDS cleanup verified"
  fi
  
  # Check ECR
  local ecr_exists=$(aws ecr describe-repositories --repository-names "rag-app" --region "$AWS_REGION" 2>/dev/null | grep -q "repositoryName" && echo "true" || echo "false")
  
  if [ "$ecr_exists" = "true" ]; then
    log_warning "ECR repository still exists"
    all_cleaned=false
  else
    log_success "ECR cleanup verified"
  fi
  
  if [ "$all_cleaned" = true ]; then
    log_success "All AWS resources have been successfully cleaned up!"
    return 0
  else
    log_warning "Some resources still exist. Manual cleanup may be required."
    return 1
  fi
}

print_summary() {
  log_section "Cleanup Summary"
  echo -e "${GREEN}Successful: $CLEANUP_SUCCESS${NC}" | tee -a "$CLEANUP_LOG"
  echo -e "${RED}Failed: $CLEANUP_FAILED${NC}" | tee -a "$CLEANUP_LOG"
  echo -e "${YELLOW}Skipped: $CLEANUP_SKIPPED${NC}" | tee -a "$CLEANUP_LOG"
  echo -e "\nCleanup log saved to: $CLEANUP_LOG" | tee -a "$CLEANUP_LOG"
}

################################################################################
# Main Execution
################################################################################

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --help)
        print_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        print_help
        exit 1
        ;;
    esac
  done
  
  # Print header
  clear
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║  RAG Application AWS Cleanup Script                        ║"
  echo "║  This script will remove all AWS resources created during  ║"
  echo "║  the RAG deployment process.                               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  # Show mode
  if [ "$DRY_RUN" = true ]; then
    log_warning "Running in DRY-RUN mode. No resources will be deleted."
  fi
  
  if [ "$FORCE" = true ]; then
    log_info "Running in FORCE mode. No confirmations will be required."
  fi
  
  # Confirmation
  if [ "$DRY_RUN" != true ] && [ "$FORCE" != true ]; then
    echo ""
    if ! confirm "This will delete all RAG AWS resources. Continue?"; then
      echo -e "${YELLOW}Cleanup cancelled.${NC}"
      exit 0
    fi
  fi
  
  # Cleanup sequence
  echo ""
  cleanup_ecs_service
  cleanup_ecs_task_definitions
  cleanup_ecs_cluster
  cleanup_alb
  cleanup_target_groups
  cleanup_rds
  cleanup_rds_subnet_group
  cleanup_ec2_instances
  cleanup_nat_gateway
  cleanup_elastic_ips
  cleanup_internet_gateway
  cleanup_security_groups
  cleanup_vpc
  cleanup_ecr_repository
  cleanup_iam_roles
  cleanup_key_pairs
  cleanup_cloudwatch
  
  # Verification
  echo ""
  verify_cleanup
  
  # Summary
  echo ""
  print_summary
  
  # Exit with appropriate code
  if [ $CLEANUP_FAILED -gt 0 ]; then
    exit 1
  else
    exit 0
  fi
}

print_help() {
  cat << EOF
RAG Application AWS Cleanup Script

Usage: ./cleanup.sh [OPTIONS]

Options:
  --dry-run    Show what would be deleted without actually deleting
  --force      Skip confirmation prompts
  --help       Show this help message

Examples:
  # Preview cleanup (dry-run)
  ./cleanup.sh --dry-run

  # Run cleanup with automatic confirmation
  ./cleanup.sh --force

  # Run cleanup with prompts
  ./cleanup.sh

Environment Variables:
  AWS_REGION       AWS region (default: us-east-1)
  CLUSTER_NAME     ECS cluster name (default: rag-cluster)

Notes:
  - This script removes ALL RAG-related AWS resources
  - RDS deletion takes 5-10 minutes
  - Check cleanup log for details: cleanup-YYYYMMDD-HHMMSS.log
  - Some resources may require additional manual cleanup

EOF
}

# Run main function
main "$@"
