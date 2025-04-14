# Systems Flake Reorganization TODO

## Project Goals
- Create a more maintainable and modular NixOS configuration
- Reduce duplication across machine configs
- Improve secret management and security
- Better organize development environments
- Add testing and documentation

## High-Priority Tasks

### 1. Module System Implementation
- [ ] Create `modules/` directory structure
  - [ ] `nixos/` for NixOS-specific modules
  - [ ] `darwin/` for MacOS-specific modules
  - [ ] `home/` for home-manager modules
- [ ] Move common configurations into appropriate modules
- [ ] Create clear documentation for each module

### 2. Profile System Creation
- [ ] Create `profiles/` directory
- [ ] Define base profiles:
  - [ ] Personal machine baseline
  - [ ] Work machine baseline
  - [ ] Server baseline
  - [ ] Gaming setup
- [ ] Update machine configurations to use profiles

### 3. Configuration Organization
- [ ] Create `common/` directory for shared configs
- [ ] Implement proper user configuration structure
- [ ] Define custom options
- [ ] Organize custom packages

## Medium-Priority Tasks

### 4. Secrets Management
- [ ] Set up proper SOPS integration
- [ ] Organize secrets by category
- [ ] Document secret management procedures
- [ ] Create secure backup strategy

### 5. Container Management
- [ ] Organize container definitions
- [ ] Create shared container configurations
- [ ] Document container deployment process

### 6. Development Environment
- [ ] Create project templates
- [ ] Standardize development tools across machines
- [ ] Improve direnv integration

## Long-Term Goals

### 7. Testing Infrastructure
- [ ] Set up basic test framework
- [ ] Create tests for critical configurations
- [ ] Implement CI/CD pipeline

### 8. Documentation
- [ ] Create comprehensive system documentation
- [ ] Document maintenance procedures
- [ ] Create troubleshooting guide

### 9. Role-Based Configurations
- [ ] Define clear system roles
- [ ] Create role-specific configurations
- [ ] Document role requirements and purposes

### 10. Darwin Integration
- [ ] Improve MacOS configuration management
- [ ] Better integrate with homebrew
- [ ] Standardize cross-platform configurations

## Machine-Specific Improvements

### Rich-Evans (HP Server)
- [ ] Organize service configurations
- [ ] Improve monitoring setup
- [ ] Document backup procedures
- [ ] Review and optimize container setup

### Marshmallow (Daily Driver)
- [ ] Optimize development environment
- [ ] Review and update user configurations
- [ ] Document system maintenance

### Total-Eclipse (Gaming PC)
- [ ] Optimize gaming-specific configurations
- [ ] Review and update graphics settings
- [ ] Document gaming setup procedures

### Bartleby
- [ ] Address boot sector issues
- [ ] Optimize for low-resource usage
- [ ] Document special considerations

### MacBooks (Cronut & Work)
- [ ] Standardize cross-platform tools
- [ ] Improve Darwin-specific configurations
- [ ] Document MacOS-specific procedures

## Notes
- Keep modular structure in mind when adding new configurations
- Maintain backward compatibility during reorganization
- Document all major changes
- Consider creating migration guides for significant changes

## References
- [NixOS Wiki](https://nixos.wiki/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Darwin Documentation](https://github.com/LnL7/nix-darwin)
- [Flakes Documentation](https://nixos.wiki/wiki/Flakes)